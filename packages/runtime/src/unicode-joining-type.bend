import Base

# Unicode Joining_Type, independent of bidirectional class.
type JoiningType is Data:
  NonJoining{}
  LeftJoining{}
  RightJoining{}
  DualJoining{}
  JoinCausing{}
  Transparent{}
