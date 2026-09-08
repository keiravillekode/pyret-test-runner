use context starter2024

include file("fail-if-a-test-errors.arr")

check "divide divides":
  divide(6, 3) is 2
end

check "divide by zero is an unexpected exception":
  divide(1, 0) is 0
end

check "explode raises boom":
  explode() raises "boom"
end

check "a check block that ends in an error":
  explode()
  1 is 1
end

check:
  divide(9, 3) is 3
end
