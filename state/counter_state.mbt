///|
// Counter state stores the current numeric value.
pub struct CounterState {
  mut value : Double
} derive(Show)

///|
pub fn CounterState::new() -> CounterState {
  CounterState::{ value: 0.0 }
}

///|
pub fn CounterState::apply(self : CounterState, delta : Double) -> Unit {
  self.value = self.value + delta
}

///|
pub fn CounterState::value(self : CounterState) -> Double {
  self.value
}

///|
pub fn CounterState::to_value(self : CounterState) -> @types.LoroValue {
  @types.LoroValue::F64(self.value)
}
