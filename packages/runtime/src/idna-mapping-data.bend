import Base

type Status is Data:
  Valid{}
  Ignored{}
  Mapped{replacement: String}
  Deviation{replacement: String}
  Disallowed{}

type Entry is Data:
  Entry{last: U32, status: Status}
