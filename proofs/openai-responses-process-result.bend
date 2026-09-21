import Base
import ../laws/openai-responses-process-result.bend as Laws

def Laws.successful_processing_retains_message(Transport, G, E, message, processing, disposal): {==}
def Laws.simultaneous_failures_retain_message_and_both_causes(Transport, G, E, message, processing, disposal, primary, secondary): {==}
