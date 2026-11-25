import
  std/[strutils, unicode]

const
  InvalidUtf8Notice = "[Invalid UTF-8 bytes are shown as \\xNN; original source bytes are retained.]\n"

proc renderUtf8Bytes*(value: string): string =
  ## Preserve valid text and visibly escape malformed historical or diagnostic bytes without changing their source.
  if validateUtf8(value) < 0: return value
  result = InvalidUtf8Notice
  var offset = 0
  while offset < value.len:
    if ord(value[offset]) < 128:
      result.add(value[offset])
      inc offset
    else:
      let width = runeLenAt(value, offset)
      if width > 1 and offset + width <= value.len and validateUtf8(value.toOpenArray(offset, offset + width - 1)) < 0:
        result.add(value[offset ..< offset + width])
        offset += width
      else:
        result.add("\\x" & ord(value[offset]).toHex(2))
        inc offset

proc utf8Prefix*(value: string, maxBytes: int): string =
  ## Bound a text prefix in bytes while retaining only complete UTF-8 characters.
  if maxBytes <= 0: return ""
  let text = renderUtf8Bytes(value)
  if text.len <= maxBytes: return text
  var finish = maxBytes
  while finish > 0 and (ord(text[finish]) and 0xC0) == 0x80: dec finish
  text[0..<finish]

proc utf8Tail*(value: string, maxBytes: int): string =
  ## Bound a text suffix in bytes while retaining only complete UTF-8 characters.
  if maxBytes <= 0: return ""
  let text = renderUtf8Bytes(value)
  if text.len <= maxBytes: return text
  var start = text.len - maxBytes
  while start < text.len and (ord(text[start]) and 0xC0) == 0x80: inc start
  text[start..^1]
