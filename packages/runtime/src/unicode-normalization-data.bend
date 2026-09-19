import Base
import ./u32-table.bend as Table

type Point is Data:
  Point{code: U32, combiningClass: U32}

type Property is Data:
  Property{combiningClass: U32, decomposition: List<&2, Point>}

type Tables is Data:
  Tables{properties: Table.Table<Property>, compositions: Table.Table<Table.Table<U32>>}
