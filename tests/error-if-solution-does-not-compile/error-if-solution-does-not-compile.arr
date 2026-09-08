use context starter2024

provide: square-of-sum end

fun square(number):
  number * number
end

fun square-of-sum(number):
  square((number * (number + 1)) / 2)
end
