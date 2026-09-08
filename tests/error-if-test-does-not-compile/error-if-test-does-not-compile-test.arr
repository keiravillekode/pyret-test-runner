use context starter2024

include file("error-if-test-does-not-compile.arr")

check "year divisible by 4":
  leap-year(1996) is true
end
