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

(: Set the child element $name of $parent to the value of the environment
 : variable $var. A missing element is added. If the variable is not set (or
 : empty) the stored value is kept.
 :)
declare function local:set-from-env (
  $parent as element(),
  $name as xs:string,
  $var as xs:string
) as empty-sequence() {
  let $value := environment-variable($var)
  let $element := $parent/*[local-name() = $name]
  return
    if (not($value)) then ()
    else if ($element) then (
      util:log-system-out("Setting " || $name || " from " || $var),
      update value $element with $value
    ) else (
      util:log-system-out("Adding " || $name || " from " || $var),
      update insert element { $name } { $value } into $parent
    )
};

(: The config file is created with default values on the first install. On
 : every install the values are then updated from the following environment
 : variables, as far as they are set:
 :
 : - ECOCOR_API_BASE: base URI the EcoCor API will be available under
 :   (default: https://ecocor.org/api)
 : - EXTRACTOR_SERVER: EcoCor extractor service URI
 :   (default: http://localhost:8040)
 :)
declare function local:update-config-file ()
as item()* {
  if (doc($config:file)/config) then ()
  else (
    util:log-system-out("Creating " || $config:file),
    local:store(
      $config:file,
      <config>
        <api-base>https://ecocor.org/api</api-base>
        <services>
          <extractor>http://localhost:8040</extractor>
        </services>
      </config>
    )
  ),
  if (doc($config:file)/config/services) then ()
  else update insert <services/> into doc($config:file)/config,
  local:set-from-env(doc($config:file)/config, "api-base", "ECOCOR_API_BASE"),
  local:set-from-env(
    doc($config:file)/config/services, "extractor", "EXTRACTOR_SERVER"
  )
};

(: elevate privileges for github webhook :)
(: let $webhook := xs:anyURI($target || '/modules/webhook.xqm') :)

(: register the RESTXQ module :)
let $restxq-module := xs:anyURI('modules/api.xpm')

return (
  local:update-config-file(),
  (: sm:chown($webhook, "admin"),
  sm:chgrp($webhook, "dba"),
  sm:chmod($webhook, 'rwsr-xr-x'), :)
  exrest:register-module($restxq-module)
)
