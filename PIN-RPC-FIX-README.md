# PIN RPC Fix

The screenshot error is caused by two RPC signatures existing at once:
- set_transaction_pin(text)
- set_transaction_pin(text, text DEFAULT NULL)

PostgREST treats the second as callable with one argument too, so the call becomes ambiguous.

## Fix
Run `FIX-PIN-RPC-AMBIGUITY.sql`, then run `PATCH-PIN-USER-MBANKING.sql`.

The final design has one setter: `set_transaction_pin(text)`, and a separate changer: `change_transaction_pin(text,text)`.
