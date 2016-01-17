TODO for CGI::Github::Webhook
=============================

* use [CGI::Test](https://metacpan.org/pod/CGI::Test) in test suite
  instead of incomplete self-written wrapper. This should also fix the
  rather bad coverage.
  * Package CGI::Test for Debian
* Provide access methods to commonly used data inside the `POST`ed JSON.
* If the trigger script is backgrounded, there's not much more control
  over what happens afterwards. It would be nice if there was some
  hook to run after the trigger script has been run and which would
  check the trigger script's exit code to e.g. change the state badge.
* Provide some kind of locking to only run one instance of the trigger
  script or at least its final syncing.
* Use [Semantic Versioning](https://semver.org/) aka `breaking.feature.fix`.
