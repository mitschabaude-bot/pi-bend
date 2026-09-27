import Base

# pi-mono auth/oauth/oauth-page.ts: the page an OAuth callback server returns
# to the browser.

def LOGO_SVG() -> String: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 800 800\" aria-hidden=\"true\"><path fill=\"#fff\" fill-rule=\"evenodd\" d=\"M165.29 165.29 H517.36 V400 H400 V517.36 H282.65 V634.72 H165.29 Z M282.65 282.65 V400 H400 V282.65 Z\"/><path fill=\"#fff\" d=\"M517.36 400 H634.72 V634.72 H517.36 Z\"/></svg>"

# escapeHtml: & < > " '
def escapeHtml(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'&', rest}: "&amp;" ++ escapeHtml(rest)
    case SCon{'<', rest}: "&lt;" ++ escapeHtml(rest)
    case SCon{'>', rest}: "&gt;" ++ escapeHtml(rest)
    case SCon{'"', rest}: "&quot;" ++ escapeHtml(rest)
    case SCon{'\'', rest}: "&#39;" ++ escapeHtml(rest)
    case SCon{c, rest}: SCon{c, escapeHtml(rest)}

def detailsBlock(details: Maybe<&2, String>) -> String:
  match details:
    case Some{SCon{c, cs}}: "<div class=\"details\">" ++ SCon{c, cs} ++ "</div>"
    case _: ""

def page(title: String, heading: String, message: String, details: Maybe<&2, String>) -> String:
    "<!doctype html>\n" ++
    "<html lang=\"en\">\n" ++
    "<head>\n" ++
    "  <meta charset=\"utf-8\" />\n" ++
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n" ++
    "  <title>" ++
    title ++
    "</title>\n" ++
    "  <style>\n" ++
    "    :root {\n" ++
    "      --text: #fafafa;\n" ++
    "      --text-dim: #a1a1aa;\n" ++
    "      --page-bg: #09090b;\n" ++
    "      --font-sans: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, \"Noto Sans\", sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\", \"Segoe UI Symbol\", \"Noto Color Emoji\";\n" ++
    "      --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace;\n" ++
    "    }\n" ++
    "    * { box-sizing: border-box; }\n" ++
    "    html { color-scheme: dark; }\n" ++
    "    body {\n" ++
    "      margin: 0;\n" ++
    "      min-height: 100vh;\n" ++
    "      display: flex;\n" ++
    "      align-items: center;\n" ++
    "      justify-content: center;\n" ++
    "      padding: 24px;\n" ++
    "      background: var(--page-bg);\n" ++
    "      color: var(--text);\n" ++
    "      font-family: var(--font-sans);\n" ++
    "      text-align: center;\n" ++
    "    }\n" ++
    "    main {\n" ++
    "      width: 100%;\n" ++
    "      max-width: 560px;\n" ++
    "      display: flex;\n" ++
    "      flex-direction: column;\n" ++
    "      align-items: center;\n" ++
    "      justify-content: center;\n" ++
    "    }\n" ++
    "    .logo {\n" ++
    "      width: 72px;\n" ++
    "      height: 72px;\n" ++
    "      display: block;\n" ++
    "      margin-bottom: 24px;\n" ++
    "    }\n" ++
    "    h1 {\n" ++
    "      margin: 0 0 10px;\n" ++
    "      font-size: 28px;\n" ++
    "      line-height: 1.15;\n" ++
    "      font-weight: 650;\n" ++
    "      color: var(--text);\n" ++
    "    }\n" ++
    "    p {\n" ++
    "      margin: 0;\n" ++
    "      line-height: 1.7;\n" ++
    "      color: var(--text-dim);\n" ++
    "      font-size: 15px;\n" ++
    "    }\n" ++
    "    .details {\n" ++
    "      margin-top: 16px;\n" ++
    "      font-family: var(--font-mono);\n" ++
    "      font-size: 13px;\n" ++
    "      color: var(--text-dim);\n" ++
    "      white-space: pre-wrap;\n" ++
    "      word-break: break-word;\n" ++
    "    }\n" ++
    "  </style>\n" ++
    "</head>\n" ++
    "<body>\n" ++
    "  <main>\n" ++
    "    <div class=\"logo\">" ++
    LOGO_SVG() ++
    "</div>\n" ++
    "    <h1>" ++
    heading ++
    "</h1>\n" ++
    "    <p>" ++
    message ++
    "</p>\n" ++
    "    " ++
    detailsBlock(details) ++
    "\n" ++
    "  </main>\n" ++
    "</body>\n" ++
    "</html>"

def renderPage(rawTitle: String, rawHeading: String, rawMessage: String, rawDetails: Maybe<&2, String>) -> String:
  page(escapeHtml(rawTitle), escapeHtml(rawHeading), escapeHtml(rawMessage), Maybe.map(&2, String, String, escapeHtml, rawDetails))

def oauthSuccessHtml(message: String) -> String: renderPage("Authentication successful", "Authentication successful", message, None{})

def oauthErrorHtml(message: String, details: Maybe<&2, String>) -> String: renderPage("Authentication failed", "Authentication failed", message, details)
