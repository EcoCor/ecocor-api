xquery version "3.1";

(:~
 : Module providing function to load files from zip archives.
 :)
module namespace load = "http://ecocor.org/ns/exist/load";

import module namespace config = "http://ecocor.org/ns/exist/config" at "config.xqm";
import module namespace ectei = "http://ecocor.org/ns/exist/tei" at "tei.xqm";
import module namespace ecutil = "http://ecocor.org/ns/exist/util" at "util.xqm";
import module namespace gh = "http://ecocor.org/ns/exist/github" at "github.xqm";

declare namespace compression = "http://exist-db.org/xquery/compression";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare function local:store(
  $path as xs:anyURI,
  $type as xs:string,
  $data as item()?,
  $param as item()*
) as item()* {
  if($data instance of document-node()) then
    let $collection := $param[1]
    let $sha := $param[2]
    let $filename := tokenize($path, "/")[last()]
    let $name := replace($filename, "\.xml$", "")
    let $log := util:log-system-out("LOADING " || $path)
    let $res := if ($name = "corpus") then
      xmldb:store($collection, "corpus.xml", $data)
    else
      let $text-collection := xmldb:create-collection($collection, $name)
      return try {
        xmldb:store($text-collection, "tei.xml", $data),
        if ($sha) then
          xmldb:store($text-collection, "git.xml", <git><sha>{$sha}</sha></git>)
        else ()
      } catch * {
        util:log-system-out($err:description)
      }
    return $res
  else
    util:log-system-out($path || " is not a document-node()")
};

declare function local:filter(
  $path as xs:anyURI, $type as xs:string, $param as item()*
) as xs:boolean {
  (: filter paths using only XML files in the "tei" subdirectory :)
  if ($type eq "resource" and (
    matches($path, "/tei/[-._a-z\d]+\.xml$", "i") or
    contains($path, "corpus.xml")
  )) then
    true()
  else
    false()
};

declare function local:record-corpus-sha($name) {
  let $sha := ecutil:get-corpus-sha($name)
  return if ($sha) then
    ecutil:record-sha($name, $sha)
  else
    ecutil:remove-corpus-sha($name)
};

(:~
 : Load corpus from ZIP archive
 :
 : @param $corpus The <corpus> element providing corpus name and archive URL
 : @return List of created collections and files
:)
declare function load:load-corpus($corpus as element(tei:teiCorpus))
as xs:string* {
  let $info := ectei:get-corpus-info($corpus)
  let $name := $info?name

  let $corpus-collection := $config:corpora-root || "/" || $name

  let $archive :=
    if ($info?archive) then map {
      "url": $info?archive
    } else if ($info?repository) then
      gh:get-archive($info?repository)
    else ()

  return
    if (not(count($archive)) or not($archive?url)) then (
      util:log-system-out("cannot determine archive URL")
    )
    else
      let $log := util:log-system-out("loading " || $archive?url)
      let $request := <hc:request method="get" href="{ $archive?url }" />
      let $response := hc:send-request($request)
      return
        if ($response[1]/@status = "200") then
          let $body := $response[2]
          let $zip := xs:base64Binary($body)
          return (
            util:log-system-out("removing " || $corpus-collection),
            xmldb:remove($corpus-collection),
            util:log-system-out("recreating " || $name),
            ecutil:create-corpus($info),

            (: load files from ZIP archive :)
            try {
              compression:unzip(
                $zip,
                util:function(xs:QName("local:filter"), 3),
                (),
                util:function(xs:QName("local:store"), 4),
                ($corpus-collection, $archive?sha)
              ),
              local:record-corpus-sha($name),
              util:log-system-out($name || " LOADED")
            } catch * {
              util:log-system-out(
                'Error [' || $err:code || ']: ' || $err:description
              )
            }
          )
        else (
          util:log("warn", ("cannot load archive ", $archive?url)),
          util:log("info", $response)
        )
};
