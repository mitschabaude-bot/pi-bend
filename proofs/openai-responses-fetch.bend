import Base
import ../laws/openai-responses-fetch.bend as Laws

def Laws.fetch_input_retains_request(Reason, url, method, headers, body, timeout, signal): {==}
def Laws.absent_custom_fetch_selects_native(Reason, E, Transport, native): {==}
def Laws.custom_fetch_takes_precedence(Reason, E, Transport, native, custom): {==}
