TODO for CGI::Github::Webhook
=============================

* use [CGI::Test](https://metacpan.org/pod/CGI::Test) in test suite
  instead of incomplete self-written wrapper. This should also fix the
  rather bad coverage.
  * Package CGI::Test for Debian
* Provide access methods to commonly used data inside the `POST`ed JSON.
* Adding support for "build passed/failed/errored" hooks to create e.g.
  buttons based on images made via [Shields.io](http://shields.io/).
