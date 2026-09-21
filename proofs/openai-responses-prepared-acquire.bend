import Base
import ../laws/openai-responses-prepared-acquire.bend as Laws

def Laws.preparation_failure_never_acquires(E, State, embed, acquire, cause): {==}
def Laws.successful_acquisition_retains_preparation_and_response(E, State, prepared, response): {==}
def Laws.acquisition_failure_is_unchanged(E, State, prepared, cause): {==}
def Laws.release_transfers_the_original_response(E, State, retire, prepared, response): {==}
