///|
// Counter operation stores an increment delta.
pub struct CounterOp {
  delta : Double
} derive(Show)

///|
pub fn CounterOp::new(delta : Double) -> CounterOp {
  CounterOp::{ delta, }
}

///|
pub fn CounterOp::delta(self : CounterOp) -> Double {
  self.delta
}
