use context starter2024

include file("error-if-solution-does-not-compile.arr")

check "square-of-sum of 5":
  square-of-sum(5) is 225
end

check "square-of-sum of 10":
  square-of-sum(10) is 3025
end
