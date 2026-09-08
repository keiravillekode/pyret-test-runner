use context starter2024

provide: expected-minutes-in-oven, remaining-minutes-in-oven, preparation-time-in-minutes end

fun expected-minutes-in-oven():
  40
end

fun remaining-minutes-in-oven(actual-minutes):
  actual-minutes - expected-minutes-in-oven()
end

fun preparation-time-in-minutes(layers):
  layers * 2
end
