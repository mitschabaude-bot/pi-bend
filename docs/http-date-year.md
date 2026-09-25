# HTTP-date year resolution

`http-date-year.resolve` implements the [RFC 9110 §5.6.7](https://www.rfc-editor.org/rfc/rfc9110.html#section-5.6.7) rolling 50-year window for RFC 850 dates. IMF-fixdate and asctime retain their literal four-digit years. The caller supplies the current UTC civil date; production uses no host date parser.

The resolver selects the most recent matching year at or before the current date's 50-year anniversary. It compares month/day/clock fields, including seconds, so the exact anniversary stays in the future century and one second beyond moves back a century. A February 29 reference uses the same month/day boundary when comparing anniversary fields; this step does not manufacture or normalize a calendar date. A selected year outside 0000–9999 fails explicitly instead of wrapping or selecting a different in-range century. Invalid reference dates retain their calendar error. The interpreter must subsequently validate the resolved date and weekday.

Four generic laws, with three supporting lemmas, establish literal-year behavior independent of the current clock, weekday independence during century selection, and preservation of invalid-reference causes. They have no unsafe annotations and are included in the 482-law root gate. These laws do not establish the complete rolling-window arithmetic.

The runtime record checks 7,224 cases on native one/four threads and Bun. Its independent oracle enumerates candidate centuries instead of repeating the implementation's division and rollback calculation. Coverage includes every two-digit year around the exact anniversary for seventeen reference years, leap-day anniversaries, random reference dates, calendar endpoints, literal years and invalid references. This is finite evidence, complementary to the laws.

[HTTP-date interpretation, weekday checking, explicit leap-second representation and the numeric retry callback](http-date.md) are now implemented; full provider integration remains pending. In particular, the RFC explicitly allows leap seconds; a complete interpreter must address them rather than treating every `23:59:60` as malformed.
