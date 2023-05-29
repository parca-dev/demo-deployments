{
  // sanitizeLabelName sanitizes a given string to be used as a Parca label name.
  // Jsonnet equivalent of: regexp.MustCompile(`[^a-zA-Z0-9_]`).ReplaceAllString(name, "_")
  sanitizeLabelName(name):
    std.join('', [
      if c >= 'a' && c <= 'z' ||
         c >= 'A' && c <= 'Z' ||
         c >= '0' && c <= '9' ||
         c == '_'
      then
        c
      else
        '_'
      for c in std.stringChars(name)
    ]),
}
