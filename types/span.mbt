///|
// Counter spans are right-open intervals: [start, end).
pub struct CounterSpan {
  start : Counter
  end : Counter
} derive(Show, Eq)

///|
pub fn CounterSpan::new(start : Counter, end : Counter) -> CounterSpan {
  CounterSpan::{ start, end }
}

///|
pub fn CounterSpan::len(self : CounterSpan) -> Int {
  if self.end >= self.start {
    self.end - self.start
  } else {
    self.start - self.end
  }
}

///|
pub fn CounterSpan::normalize(self : CounterSpan) -> CounterSpan {
  if self.end >= self.start {
    self
  } else {
    CounterSpan::{ start: self.end, end: self.start }
  }
}

///|
pub fn CounterSpan::contains(self : CounterSpan, counter : Counter) -> Bool {
  let norm = self.normalize()
  norm.start <= counter && counter < norm.end
}

///|
// ID span for a peer over a counter range.
pub struct IdSpan {
  peer : PeerID
  counter : CounterSpan
} derive(Show, Eq)

///|
pub fn IdSpan::new(peer : PeerID, start : Counter, end : Counter) -> IdSpan {
  IdSpan::{ peer, counter: CounterSpan::new(start, end) }
}
