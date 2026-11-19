## Validate prompt images and keep their bytes in private, content-addressed files.
##
## Transcripts reference images only by SHA-256 digest; the digest alone selects
## the file, and every read re-verifies size, digest, type and dimensions.

import
  std/[base64, json, os, strutils],
  acport, crunchy,
  ./agent_sessions

const
  MaxImageBytes* = 4 * 1024 * 1024
  MaxImageDimension* = 8000
  MaxMessageImages* = 8
  MaxPromptImageBytes* = 16 * 1024 * 1024
  DigestLength = 64
  MediaSuffix = "-media"
  PrivateDirectory = {fpUserRead, fpUserWrite, fpUserExec}
  PrivateFile = {fpUserRead, fpUserWrite}

type
  ImageInfo* = object
    mimeType*: string
    width*, height*: int

  StoredImage* = object
    ## A validated image with its decoded bytes and durable reference.
    bytes*: string
    sha256*: string
    info*: ImageInfo

proc readBigEndian(data: string, offset, size: int): int =
  ## Decode an unsigned big-endian integer within bounds the caller checked.
  for index in 0..<size: result = (result shl 8) or ord(data[offset + index])

proc readLittleEndian(data: string, offset, size: int): int =
  ## Decode an unsigned little-endian integer within bounds the caller checked.
  for index in countdown(size - 1, 0): result = (result shl 8) or ord(data[offset + index])

proc pngInfo(data: string): ImageInfo =
  ## Read PNG dimensions from the mandatory IHDR chunk and require an IEND trailer.
  if data.len < 45 or data[12..15] != "IHDR" or readBigEndian(data, 8, 4) != 13:
    raise newException(ValueError, "PNG header is incomplete")
  if data[^8..^5] != "IEND": raise newException(ValueError, "PNG data is truncated")
  ImageInfo(mimeType: "image/png", width: readBigEndian(data, 16, 4), height: readBigEndian(data, 20, 4))

proc jpegInfo(data: string): ImageInfo =
  ## Walk JPEG marker segments to the first frame header.
  var
    position = 2
    found = false
  while not found and position + 4 <= data.len:
    if data[position] != '\xFF': raise newException(ValueError, "JPEG marker structure is invalid")
    while position < data.len and data[position] == '\xFF': inc position
    if position >= data.len: break
    let marker = ord(data[position])
    inc position
    if marker == 0xD9 or marker == 0xDA: break
    if marker in 0xD0..0xD7 or marker == 0x01: continue
    if position + 2 > data.len: break
    let length = readBigEndian(data, position, 2)
    if length < 2 or position + length > data.len: break
    if marker in 0xC0..0xCF and marker notin [0xC4, 0xC8, 0xCC]:
      if length < 7: break
      result = ImageInfo(mimeType: "image/jpeg", height: readBigEndian(data, position + 3, 2),
        width: readBigEndian(data, position + 5, 2))
      found = true
    position += length
  if not found: raise newException(ValueError, "JPEG frame header is missing")

proc webpInfo(data: string): ImageInfo =
  ## Read the canvas or frame dimensions of lossy, lossless and extended WebP files.
  if data.len < 30 or readLittleEndian(data, 4, 4) + 8 > data.len:
    raise newException(ValueError, "WebP data is truncated")
  result.mimeType = "image/webp"
  case data[12..15]
  of "VP8 ":
    if data[23..25] != "\x9D\x01\x2A": raise newException(ValueError, "WebP frame header is invalid")
    result.width = readLittleEndian(data, 26, 2) and 0x3FFF
    result.height = readLittleEndian(data, 28, 2) and 0x3FFF
  of "VP8L":
    if data[20] != '\x2F': raise newException(ValueError, "WebP lossless header is invalid")
    let bits = readLittleEndian(data, 21, 4)
    result.width = (bits and 0x3FFF) + 1
    result.height = ((bits shr 14) and 0x3FFF) + 1
  of "VP8X":
    result.width = readLittleEndian(data, 24, 3) + 1
    result.height = readLittleEndian(data, 27, 3) + 1
  else: raise newException(ValueError, "WebP image chunk is missing")

proc inspectImage*(data: string): ImageInfo =
  ## Validate image bytes by signature, size and dimensions; declared types are not trusted.
  if data.len == 0: raise newException(ValueError, "Image is empty")
  if data.len > MaxImageBytes:
    raise newException(ValueError, "Image exceeds " & $(MaxImageBytes div (1024 * 1024)) & " MiB")
  result = if data.startsWith("\x89PNG\r\n\x1A\n"): pngInfo(data)
    elif data.startsWith("\xFF\xD8\xFF"): jpegInfo(data)
    elif data.len >= 12 and data.startsWith("RIFF") and data[8..11] == "WEBP": webpInfo(data)
    else: raise newException(ValueError, "Only PNG, JPEG and WebP images are supported")
  if result.width notin 1..MaxImageDimension or result.height notin 1..MaxImageDimension:
    raise newException(ValueError, "Image dimensions must be between 1 and " &
      $MaxImageDimension & " pixels")

proc sha256Hex(data: string): string =
  ## Encode the SHA-256 digest of data as lowercase hexadecimal.
  for value in sha256(data): result.add(toHex(value.int, 2).toLowerAscii())

proc validateImage*(content: ContentBlock): StoredImage =
  ## Decode and validate one prompt image, requiring its declared type to match its bytes.
  if content.data.len > (MaxImageBytes + 2) div 3 * 4 + 4:
    raise rpcError(InvalidParams, "Image exceeds " & $(MaxImageBytes div (1024 * 1024)) & " MiB")
  try:
    result.bytes = decode(content.data)
    result.info = inspectImage(result.bytes)
  except ValueError as error:
    raise rpcError(InvalidParams, "Invalid image: " & error.msg)
  if content.mimeType != result.info.mimeType:
    raise rpcError(InvalidParams, "Image type " & content.mimeType & " does not match its " &
      result.info.mimeType & " data")
  result.sha256 = sha256Hex(result.bytes)

proc mediaDirectory*(stateDirectory, sessionId: string): string =
  ## Locate a validated session's private media directory.
  stateDirectory / (sessionId & MediaSuffix)

proc requireDigest(digest: string) =
  ## Accept only full lowercase SHA-256 digests so references cannot name other paths.
  if digest.len != DigestLength or not digest.allCharsInSet({'0'..'9', 'a'..'f'}):
    raise newException(ValueError, "Invalid image reference")

proc storeImage*(directory: string, image: StoredImage) =
  ## Durably write image bytes under their digest in a private directory, reusing identical files.
  requireDigest(image.sha256)
  if not dirExists(directory):
    createDir(directory)
  setFilePermissions(directory, PrivateDirectory)
  let path = directory / image.sha256
  if not fileExists(path):
    atomicRuntimeWrite(path, image.bytes)
  setFilePermissions(path, PrivateFile)

proc imageReference*(image: StoredImage): JsonNode =
  ## Describe a stored image for the transcript without its bytes.
  %*{"type": "image", "mimeType": image.info.mimeType, "sha256": image.sha256,
    "bytes": image.bytes.len, "width": image.info.width, "height": image.info.height}

proc loadImage*(directory: string, reference: JsonNode): ContentBlock =
  ## Read a referenced image after re-verifying its digest, size, type and dimensions.
  let digest = reference{"sha256"}.getStr()
  requireDigest(digest)
  let path = directory / digest
  if getFileInfo(path, followSymlink = false).kind != pcFile:
    raise newException(ValueError, "Image reference is not a regular file")
  if getFileSize(path) > MaxImageBytes:
    raise newException(ValueError, "Stored image exceeds the size limit")
  let bytes = readFile(path)
  if sha256Hex(bytes) != digest or bytes.len != reference{"bytes"}.getInt(-1):
    raise newException(ValueError, "Stored image does not match its reference")
  let info = inspectImage(bytes)
  if info.mimeType != reference{"mimeType"}.getStr():
    raise newException(ValueError, "Stored image type does not match its reference")
  ContentBlock(kind: imageContent, data: encode(bytes), mimeType: info.mimeType)
