use context starter2024

include file("fail-if-a-task-fails.arr")

check "expected minutes in oven":
  ## task 1
  expected-minutes-in-oven() is 40
end

check "remaining minutes in oven":
  ## task 2
  remaining-minutes-in-oven(25) is 15
end

check "remaining minutes in oven when just put in":
  ## task 2
  remaining-minutes-in-oven(0) is 40
end

check "preparation time in minutes for one layer":
  ## task 3
  preparation-time-in-minutes(1) is 2
end

check "total time for two layers, not linked to a task":
  preparation-time-in-minutes(2) + remaining-minutes-in-oven(30) is 14
end
