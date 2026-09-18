import Base
import ./types.bend as T
import ./agent-queues.bend as Q
import ../../ai/src/types.bend as Ai

# A pure decision consumed by the Agent owner when it claims the next run.
# Planning and queue changes must be committed together with that run claim.
type ContinueError is Data:
  Busy{}
  NoMessages{}
  AssistantTail{}
def errorMessage(error: ContinueError) -> String:
  match error:
    case Busy{}: "Agent is already processing. Wait for completion before continuing."
    case NoMessages{}: "No messages to continue from"
    case AssistantTail{}: "Cannot continue from message role: assistant"

type Plan<-M: Data> is Data:
  Prompt{messages: List<&2, M>, skipInitialSteeringPoll: Bool}
  Continue{}
type Tail is Data:
  Empty{}
  Assistant{}
  Other{}

def isSystem(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, message: T.AgentMessage<P, A, G, D, C>) -> Bool:
  match message:
    case T.LlmMessage{Ai.System{_}}: True{}
    case _: False{}
def finalTail(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, nonSystem: Bool, message: T.AgentMessage<P, A, G, D, C>) -> Tail:
  match message:
    case T.LlmMessage{Ai.Assistant{_}}: Assistant{}
    case _: Bool.pick(Tail, nonSystem, Other{}, Empty{})
def tail(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, messages: List<&2, T.AgentMessage<P, A, G, D, C>>, nonSystem: Bool) -> Tail:
  match messages:
    case Nil{}: Empty{}
    case +last <> Nil{}: finalTail(P, A, G, D, C, nonSystem || Bool.not(isSystem(P, A, G, D, C, last)), last)
    case message <> rest: tail(P, A, G, D, C, rest, nonSystem || Bool.not(isSystem(P, A, G, D, C, message)))

def followUpPlan(-M: Data, drained: Q.Queues<M> & List<&2, M>) -> Q.Queues<M> & Result<&2, &2, ContinueError, Plan<M>>:
  match drained:
    case Tuple{queues, Nil{}}: (queues, Fail{AssistantTail{}})
    case Tuple{queues, head <> rest}: (queues, Done{Prompt{head <> rest, False{}}})
def steeringPlan(-M: Data, drained: Q.Queues<M> & List<&2, M>) -> Q.Queues<M> & Result<&2, &2, ContinueError, Plan<M>>:
  match drained:
    case Tuple{queues, Nil{}}: followUpPlan(M, Q.drain(M, queues, Q.FollowUp{}))
    case Tuple{queues, head <> rest}: (queues, Done{Prompt{head <> rest, True{}}})
def planTail(-M: Data, queues: Q.Queues<M>, last: Tail) -> Q.Queues<M> & Result<&2, &2, ContinueError, Plan<M>>:
  match last:
    case Empty{}: (queues, Fail{NoMessages{}})
    case Assistant{}: steeringPlan(M, Q.drain(M, queues, Q.Steering{}))
    case Other{}: (queues, Done{Continue{}})
def plan(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, active: Bool, messages: List<&2, T.AgentMessage<P, A, G, D, C>>, queues: Q.Queues<T.AgentMessage<P, A, G, D, C>>) -> Q.Queues<T.AgentMessage<P, A, G, D, C>> & Result<&2, &2, ContinueError, Plan<T.AgentMessage<P, A, G, D, C>>>:
  match active:
    case True{}: (queues, Fail{Busy{}})
    case False{}: planTail(T.AgentMessage<P, A, G, D, C>, queues, tail(P, A, G, D, C, messages, False{}))
