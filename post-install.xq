xquery version "3.1";

import module namespace config = "http://ecocor.org/ns/exist/config"
  at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)
(: the target collection into which the app is deployed :)
declare variable $target external;

declare function local:store ($file-path, $content) {
  let $segments := tokenize($file-path, '/')
  let $name := $segments[last()]
  let $col := substring($file-path, 1, string-length($file-path) - string-length($name) - 1)
  return xmldb:store($col, $name, $content)
};

(: We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - ECOCOR_API_BASE: base URI the EcoCor API will be available under
 : - EXTRACTOR_SERVER: EcoCor extractor service URI
 :)
declare function local:create-config-file ()
as item()? {
  if(doc($config:file)/config) then
    ()
  else
    util:log-system-out("Creating " || $config:file),
    local:store(
      $config:file,
      <config>
        <api-base>
        {
          if (environment-variable("ECOCOR_API_BASE")) then
            environment-variable("ECOCOR_API_BASE")
          else "https://ecocor.org/api"
        }
        </api-base>
        <services>
          <extractor>
          {
            if (environment-variable("EXTRACTOR_SERVER")) then
              environment-variable("EXTRACTOR_SERVER")
            else "http://localhost:8040"
          }
          </extractor>
        </services>
      </config>
    )
};

(: We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - GITHUB_WEBHOOK_SECRET: secret for the GitHub webhook
 :)
declare function local:create-secrets-file ()
as item()? {
  if(doc($config:secrets-file)/secrets) then
    ()
  else (
    util:log-system-out("Creating " || $config:secrets-file),
    local:store(
      $config:secrets-file,
      <secrets>
        <gh-webhook>{environment-variable("GITHUB_WEBHOOK_SECRET")}</gh-webhook>
      </secrets>
    ),
    sm:chmod(xs:anyURI($config:secrets-file), 'rw-------')
  )
};

(: elevate privileges for github webhook :)
(: let $webhook := xs:anyURI($target || '/modules/webhook.xqm') :)

(: register the RESTXQ module :)
let $restxq-module := xs:anyURI('modules/api.xpm')

return (
  local:create-config-file(),
  local:create-secrets-file(),
  (: sm:chown($webhook, "admin"),
  sm:chgrp($webhook, "dba"),
  sm:chmod($webhook, 'rwsr-xr-x'), :)
  exrest:register-module($restxq-module)
)
