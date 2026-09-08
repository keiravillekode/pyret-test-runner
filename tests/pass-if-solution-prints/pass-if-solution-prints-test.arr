use context starter2024

include file("pass-if-solution-prints.arr")

check "greets by name":
  greet("Alice") is "Hello, Alice!"
end

check "greets again without a trailing newline":
  print("no newline after this")
  greet("Bob") is "Hello, Bob!"
end
