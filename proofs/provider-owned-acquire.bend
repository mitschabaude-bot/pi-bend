import Base
import ../laws/provider-owned-acquire.bend as Laws

def Laws.preparation_failure_skips_initialization(P, Initialization, E, Runtime, Response, initialize, acquire, retire, cause): {==}
def Laws.initialization_failure_skips_acquisition(P, Initialization, E, Runtime, Response, payload, acquire, retire, cause): {==}
def Laws.acquisition_failure_retires_runtime_before_return(Initialization, E, Runtime, Response, retire, runtime, cause): {==}
def Laws.success_transfers_runtime_and_response(Initialization, E, Runtime, Response, retire, runtime, response): {==}
def Laws.response_close_precedes_runtime_retirement(E, Runtime, Response, close, retire, runtime, response): {==}
