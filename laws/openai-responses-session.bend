import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-session.bend as Session
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/runtime/src/callback.bend as C

law publication_preserves_event:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for event: T.AssistantMessageEvent<A, G>
  {Session.publish(A, G, E, stream, event) == IO.bind(Unit, Result<&2, &2, E, Unit>, Events.push(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, event), ignored => IO.pure(Result<&2, &2, E, Unit>, Done{Unit{}})) : IO(Result<&2, &2, E, Unit>)}

law end_supplies_final_snapshot:
  for -A: Data
  for -G: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for output: T.AssistantMessage<A, G>
  {Session.end(A, G, stream, output) == Events.end(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, Some{output}) : IO(Unit)}

law borrow_running_preserves_task_and_stream:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for task: Chan(Life.RunResult<A, G, E>)
  {Session.borrow(A, G, E, Session.Running{stream, task}) == (Session.Running{stream, task}, stream) : Session.Run<A, G, E> & Events.AssistantMessageEventStream(A, G)}

law borrow_finished_preserves_result_and_stream:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for result: Life.RunResult<A, G, E>
  {Session.borrow(A, G, E, Session.Finished{stream, result}) == (Session.Finished{stream, result}, stream) : Session.Run<A, G, E> & Events.AssistantMessageEventStream(A, G)}

law completion_retains_run_result:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for result: Life.RunResult<A, G, E>
  {Session.completed(A, G, E, stream, result) == (Session.Finished{stream, result}, result) : Session.Run<A, G, E> & Life.RunResult<A, G, E>}

law finished_wait_has_no_effects:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for result: Life.RunResult<A, G, E>
  {Session.wait(A, G, E, Session.Finished{stream, result}) == IO.pure(Session.Run<A, G, E> & Life.RunResult<A, G, E>, (Session.Finished{stream, result}, result)) : IO(Session.Run<A, G, E> & Life.RunResult<A, G, E>)}

law running_wait_joins_before_completion:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for task: Chan(Life.RunResult<A, G, E>)
  {Session.wait(A, G, E, Session.Running{stream, task}) == IO.bind(Life.RunResult<A, G, E>, Session.Run<A, G, E> & Life.RunResult<A, G, E>, IO.join(Life.RunResult<A, G, E>, task), result => IO.pure(Session.Run<A, G, E> & Life.RunResult<A, G, E>, Session.completed(A, G, E, stream, result))) : IO(Session.Run<A, G, E> & Life.RunResult<A, G, E>)}

law callbacks_retire_before_run_result:
  for -A: Data
  for -G: Data
  for -E: Data
  for sink: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>
  for finish: C.Callback<T.AssistantMessage<A, G>, Unit>
  for result: Life.RunResult<A, G, E>
  {Session.retire(A, G, E, sink, finish, result) == IO.bind(Unit, Life.RunResult<A, G, E>, C.dispose(T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>, sink), ignored => IO.bind(Unit, Life.RunResult<A, G, E>, C.dispose(T.AssistantMessage<A, G>, Unit, finish), unused => IO.pure(Life.RunResult<A, G, E>, result))) : IO(Life.RunResult<A, G, E>)}

law finished_disposal_preserves_result:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for result: Life.RunResult<A, G, E>
  {Session.dispose(A, G, E, Session.Finished{stream, result}) == IO.bind(Unit, Life.RunResult<A, G, E>, Events.disposeAssistantMessageEventStream(A, G, stream), ignored => IO.pure(Life.RunResult<A, G, E>, result)) : IO(Life.RunResult<A, G, E>)}

law running_disposal_joins_before_stream_retirement:
  for -A: Data
  for -G: Data
  for -E: Data
  for stream: Events.AssistantMessageEventStream(A, G)
  for task: Chan(Life.RunResult<A, G, E>)
  {Session.dispose(A, G, E, Session.Running{stream, task}) == IO.bind(Life.RunResult<A, G, E>, Life.RunResult<A, G, E>, IO.join(Life.RunResult<A, G, E>, task), result => IO.bind(Unit, Life.RunResult<A, G, E>, Events.disposeAssistantMessageEventStream(A, G, stream), ignored => IO.pure(Life.RunResult<A, G, E>, result))) : IO(Life.RunResult<A, G, E>)}
