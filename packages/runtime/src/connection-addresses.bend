import Base
import ./abortable-connect.bend as Connect
import ./hosts.bend as Hosts
import ./hosts-file.bend as File
import ./dns-address-answer.bend as DNS

# Hosts order is already one sequence. DNS families remain separate until the
# connection scheduler explicitly chooses its interleaving/preference policy.
type Candidates is Data:
  Ordered{first: Connect.Address, rest: List<&2, Connect.Address>}
  Paired{ipv4: List<&2, Connect.Address>, ipv6: List<&2, Connect.Address>}

type Plan<-Report: Data> is Data:
  NoAddresses{report: Report}
  Addresses{report: Report, candidates: Candidates}

def ordered(-Report: Data, report: Report, addresses: List<&2, Connect.Address>) -> Plan<Report>:
  match addresses:
    case Nil{}: NoAddresses{report}
    case first <> rest: Addresses{report, Ordered{first, rest}}

def paired(-Report: Data, report: Report, ipv4: List<&2, Connect.Address>, ipv6: List<&2, Connect.Address>) -> Plan<Report>:
  match ipv4 ipv6:
    case Nil{} Nil{}: NoAddresses{report}
    case first <> rest other: Addresses{report, Paired{first <> rest, other}}
    case Nil{} first <> rest: Addresses{report, Paired{Nil{}, first <> rest}}

def local(address: File.Address) -> Connect.Address:
  match address:
    case File.V4{value}: Connect.V4{value}
    case File.V6{value}: Connect.V6{value, 0}

def host(entry: Hosts.Entry<File.Address>) -> Connect.Address:
  match entry:
    case Hosts.Entry{address, _, _}: local(address)

def hosts(entries: List<&2, Hosts.Entry<File.Address>>) -> List<&2, Connect.Address>:
  match entries:
    case Nil{}: Nil{}
    case first <> rest: host(first) <> hosts(rest)

def answer(address: DNS.Address) -> Connect.Address:
  match address:
    case DNS.V4{value, _}: Connect.V4{value}
    case DNS.V6{value, _}: Connect.V6{value, 0}

def answers(addresses: List<&2, DNS.Address>) -> List<&2, Connect.Address>:
  match addresses:
    case Nil{}: Nil{}
    case first <> rest: answer(first) <> answers(rest)
