# False positives from test support files.
#
# ExUnit macros (__using__, assert, on_exit, etc.) generate functions at
# runtime that Dialyzer cannot see during static analysis. All warnings
# originating from test/support/ are suppressed here.
#
# Additionally, Taniwha.LogCapture implements an :logger handler callback
# in a way that triggers contract/no_return warnings due to the OTP logger
# handler spec being narrower than the dynamic config map we pass.
[
  ~r"test/support/"
]
