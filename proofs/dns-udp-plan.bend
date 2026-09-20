import Base
import ../laws/dns-udp-plan.bend as Laws

def Laws.assignment_preserves_payloads(Server, servers):
  match servers:
    case Nil{}: {==}
    case _ <> Nil{}: {==}
    case _ <> _ <> Nil{}: {==}
    case _ <> _ <> _ <> Nil{}: {==}
    case _ <> _ <> _ <> _ <> _: {==}

def Laws.timing_preserves_identity(Server, server, position, duration): {==}
def Laws.invalid_layout_stops_preparation(Server, timeout, error): {==}
