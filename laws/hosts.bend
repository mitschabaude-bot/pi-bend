import Base
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts-file.bend as File

law lookup_empty:
  for -Address: Data
  for name: String
  {Hosts.lookup(Address, name, Nil{}) == Nil{} : List<&2, Hosts.Entry<Address>>}

# Combining databases preserves exactly the concatenated lookup results.
# This includes duplicate entries and the ordering of addresses and aliases.
law lookup_append:
  for -Address: Data
  for +name: String
  for +left: List<&2, Hosts.Entry<Address>>
  for +right: List<&2, Hosts.Entry<Address>>
  {Hosts.lookup(Address, name, List.append(&2, Hosts.Entry<Address>, left, right)) == List.append(&2, Hosts.Entry<Address>, Hosts.lookup(Address, name, left), Hosts.lookup(Address, name, right)) : List<&2, Hosts.Entry<Address>>}

law parse_failure_retained:
  for remaining: List<&2, String>
  for number: Nat
  for +error: File.Failure
  {File.lines(remaining, number, Fail{error}) == Fail{error} : Result<&2, &2, File.Failure, List<&2, Hosts.Entry<File.Address>>>}

law invalid_line_discards_partial_database:
  for +number: Nat
  for prior: List<&2, Hosts.Entry<File.Address>>
  for +error: File.Error
  {File.accepted(number, prior, Fail{error}) == Fail{File.Failure{number, error}} : Result<&2, &2, File.Failure, List<&2, Hosts.Entry<File.Address>>>}

law canonical_matches:
  for -Address: Data
  for address: Address
  for +name: String
  for aliases: List<&2, String>
  {True{} == Hosts.matches(Address, name, Hosts.Entry{address, name, aliases}) : Bool}

law first_alias_matches:
  for -Address: Data
  for address: Address
  for +name: String
  for canonical: String
  for aliases: List<&2, String>
  {True{} == Hosts.matches(Address, name, Hosts.Entry{address, canonical, name <> aliases}) : Bool}

law matched_entry_retained:
  for -Address: Data
  for +entry: Hosts.Entry<Address>
  for +rest: List<&2, Hosts.Entry<Address>>
  {Hosts.selected(Address, True{}, entry, rest) == entry <> rest : List<&2, Hosts.Entry<Address>>}
