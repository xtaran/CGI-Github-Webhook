TODO for CGI::Github::Webhook
=============================

* use [CGI::Test](https://metacpan.org/pod/CGI::Test) in test suite
  instead of incomplete self-written wrapper. This should also fix the
  rather bad coverage.
  * Package CGI::Test for Debian
* Provide access methods to commonly used data inside the `POST`ed JSON.
