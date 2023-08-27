xquery version "3.1";

module namespace api = "http://ecocor.org/ns/exist/api";

import module namespace config = "http://ecocor.org/ns/exist/config" at "config.xqm";
import module namespace ecutil = "http://ecocor.org/ns/exist/util" at "util.xqm";
import module namespace ectei = "http://ecocor.org/ns/exist/tei" at "tei.xqm";
import module namespace entities = "http://ecocor.org/ns/exist/entities" at "entities.xqm";
import module namespace metrics = "http://ecocor.org/ns/exist/metrics" at "metrics.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace repo = "http://exist-db.org/xquery/repo";
declare namespace expath = "http://expath.org/ns/pkg";
declare namespace json = "http://www.w3.org/2013/XSL/json";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : API info
 :
 : Shows version numbers of the ecocor-api app and the underlying eXist-db.
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/ecocor/info")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:info() {
  let $expath := config:expath-descriptor()
  let $repo := config:repo-descriptor()
  return map {
    "name": $expath/expath:title/string(),
    "version": $expath/@version/string(),
    "status": $repo/repo:status/string(),
    "existdb": system:get-version(),
    "base": $config:api-base
  }
};

(:~
 : OpenAPI specification
 :
 : @result YAML
 :)
declare
  %rest:GET
  %rest:path("/ecocor/openapi.yaml")
  %rest:produces("application/yaml")
  %output:media-type("application/yaml")
  %output:method("text")
function api:openapi-yaml() {
  let $path := $config:app-root || "/api.yaml"
  let $expath := config:expath-descriptor()
  let $yaml := util:base64-decode(xs:string(util:binary-doc($path)))
  return replace(
    replace($yaml, 'https://ecocor.org/api', $config:api-base),
    'version: [0-9.]+',
    'version: ' || $expath/@version/string()
  )
};

(:~
 : List available corpora
 :
 : @result JSON array of objects
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora() {
  array {
    for $corpus in collection($config:data-root)//tei:teiCorpus
    let $info := ectei:get-corpus-info($corpus)
    let $name := $info?name
    order by $name
    return map:merge ((
      $info,
      map:entry("uri", $config:api-base || '/corpora/' || $name),
      map:entry("metrics", metrics:corpus($name))
    ))
  }
};

(:~
 : Add new corpus
 :
 : @param $data corpus.xml containing teiCorpus element.
 : @result XML document
 :)
declare
  %rest:POST("{$data}")
  %rest:path("/ecocor/corpora")
  %rest:header-param("Authorization", "{$auth}")
  %rest:consumes("application/xml", "text/xml")
  %rest:produces("application/json")
  %output:method("json")
function api:corpora-post-tei($data, $auth) {
  if (not($auth)) then
    (
      <rest:response>
        <http:response status="401"/>
      </rest:response>,
      map {
        "message": "authorization required"
      }
    )
  else

  let $header := $data//tei:teiCorpus/tei:teiHeader
  let $name := $header//tei:publicationStmt/tei:idno[
    @type = "URI" and @xml:base = "https://ecocor.org/"
  ]/text()

  let $title := $header//tei:titleStmt/tei:title[1]/text()

  return if (not($header)) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "invalid document, expecting <teiCorpus>"
      }
    )
  else if (not($name) or not($title)) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "missing name or title"
      }
    )
  else if (not(matches($name, '^[-a-z0-1]+$'))) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "invalid name",
        "message": "Only lower case ASCII letters and digits are accepted."
      }
    )
  else
    let $corpus := ectei:get-corpus($name)
    return if ($corpus) then (
      <rest:response>
        <http:response status="409"/>
      </rest:response>,
      map {
        "error": "corpus already exists"
      }
    ) else (
      let $tei-dir := concat($config:data-root, '/', $name)
      return (
        util:log-system-out("creating corpus"),
        util:log-system-out($data),
        xmldb:create-collection($config:data-root, $name),
        xmldb:create-collection($config:entities-root, $name),
        xmldb:create-collection($config:metrics-root, $name),
        xmldb:store($tei-dir, "corpus.xml", $data),
        map {
          "name": $name,
          "title": $title
        }
      )
    )
};

(:~
 : Add new corpus
 :
 : @param $data JSON object describing corpus meta data
 : @result JSON object
 :)
declare
  %rest:POST("{$data}")
  %rest:path("/ecocor/corpora")
  %rest:consumes("application/json")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora-post-json($data) {
  let $json := parse-json(util:base64-decode($data))
  let $name := $json?name
  let $description := $json?description
  let $corpus := ectei:get-corpus($name)

  return if ($corpus) then
    (
      <rest:response>
        <http:response status="409"/>
      </rest:response>,
      map {
        "error": "corpus already exists"
      }
    )
  else if (not($name) or not($json?title)) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "missing name or title"
      }
    )
  else if (not(matches($name, '^[-a-z0-1]+$'))) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "invalid name",
        "message": "Only lower case ASCII letters and digits are accepted."
      }
    )
  else
    let $corpus :=
      <teiCorpus xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader>
          <fileDesc>
            <titleStmt>
              <title>{$json?title}</title>
            </titleStmt>
            <publicationStmt>
              <idno type="URI" xml:base="https://ecocor.org/">{$name}</idno>
              {
                if ($json?repository)
                then <idno type="repo">{$json?repository}</idno>
                else ()
              }
            </publicationStmt>
          </fileDesc>
          {if ($json?description) then (
            <encodingDesc>
              <projectDesc>
                {
                  for $p in tokenize($json?description, "&#10;&#10;")
                  return <p>{$p}</p>
                }
              </projectDesc>
            </encodingDesc>
          ) else ()}
        </teiHeader>
      </teiCorpus>
    let $tei-dir := concat($config:data-root, '/', $name)
    return (
      util:log-system-out("creating corpus"),
      util:log-system-out($corpus),
      xmldb:create-collection($config:data-root, $name),
      xmldb:create-collection($config:entities-root, $name),
      xmldb:create-collection($config:metrics-root, $name),
      xmldb:store($tei-dir, "corpus.xml", $corpus),
      $json
    )
};

(:~
 : Corpus meta data
 :
 : @param $corpusname
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpus-data($corpusname) {
  let $corpus := ectei:get-corpus-info-by-name($corpusname)
  let $metrics := metrics:corpus($corpusname)
  let $collection := concat($config:data-root, "/", $corpusname)
  return
    if (not($corpus?name) or not(xmldb:collection-available($collection))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      map:merge((
        $corpus,
        map {"metrics": $metrics}
      ))
};

(:~
 : Load corpus data from its repository
 :
 : Sending a POST request to the corpus URI reloads the data for this corpus
 : from its repository (if defined). This endpoint requires authorization.
 :
 : @param $corpusname Corpus name
 : @param $auth Authorization header value
 : @result JSON object
 :)
declare
  %rest:POST
  %rest:path("/ecocor/corpora/{$corpusname}")
  %rest:header-param("Authorization", "{$auth}")
  %output:method("json")
function api:post-corpus($corpusname, $auth) {
  if (not($auth)) then
    (
      <rest:response>
        <http:response status="401"/>
      </rest:response>,
      map {
        "message": "authorization required"
      }
    )
  else

  let $corpus := ectei:get-corpus-info-by-name($corpusname)

  return
    if (not($corpus?name)) then
      (
        <rest:response><http:response status="404"/></rest:response>,
        map {"message": "no such corpus"}
      )
    else
      let $job-name := "load-corpus-" || $corpusname
      let $params := (
        <parameters>
          <param name="corpusname" value="{$corpusname}"/>
        </parameters>
      )

      (: delete completed job before scheduling new one :)
      (: NB: usually this seems to happen automatically but apparently we
       : cannot rely on it. :)
      let $jobs := scheduler:get-scheduled-jobs()
      let $complete := $jobs//scheduler:job
        [@name=$job-name and scheduler:trigger/state = 'COMPLETE']
      let $log := if ($complete) then (
        util:log("info", "deleting completed job"),
        scheduler:delete-scheduled-job($job-name)
      ) else ()

      let $result := scheduler:schedule-xquery-periodic-job(
        $config:app-root || "/jobs/load-corpus.xq",
        1, $job-name, $params, 0, 0
      )

      return if ($result) then
        (
          <rest:response><http:response status="202"/></rest:response>,
          map {"message": "corpus update scheduled"}
        )
      else
        (
          <rest:response><http:response status="409"/></rest:response>,
          map {"message": "cannot schedule update"}
        )
};

(:~
 : Remove corpus from database
 :
 : @param $corpusname Corpus name
 : @param $auth Authorization header value
 : @result JSON object
 :)
declare
  %rest:DELETE
  %rest:path("/ecocor/corpora/{$corpusname}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:delete-corpus($corpusname, $auth) {
  if (not($auth)) then
    (
      <rest:response>
        <http:response status="401"/>
      </rest:response>,
      map {
        "message": "authorization required"
      }
    )
  else

  let $corpus := ectei:get-corpus($corpusname)

  return
    if (not($corpus)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $url := $config:data-root || "/" || $corpusname || "/corpus.xml"
      return
        if ($url = $corpus/base-uri()) then
        (
          xmldb:remove($config:data-root || "/" || $corpusname),
          xmldb:remove($config:entities-root || "/" || $corpusname),
          xmldb:remove($config:metrics-root || "/" || $corpusname),
          map {
            "message": "corpus deleted",
            "uri": $url
          }
        )
        else
        (
          <rest:response>
            <http:response status="404"/>
          </rest:response>
        )
};

(:~
 : List corpus contents
 :
 : @param $corpusname
 : @result array of JSON object
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpus-texts($corpusname) {
  let $corpus := ectei:get-corpus-info-by-name($corpusname)
  let $collection := concat($config:data-root, "/", $corpusname)
  return
    if (not($corpus?name) or not(xmldb:collection-available($collection))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      array {ectei:get-corpus-text-info($corpusname)}
};

(:~
 : List corpus entities
 :
 : @param $corpusname
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/entities")
  %rest:query-param("type", "{$type}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpus-entities($corpusname, $type) {
  let $corpus := ectei:get-corpus-info-by-name($corpusname)
  let $collection := concat($config:data-root, "/", $corpusname)
  return
    if (not($corpus?name) or not(xmldb:collection-available($collection))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      entities:corpus($corpusname, $type)
};

(:~
 : Get metadata for a single text
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @result JSON object with text meta data
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:text-info($corpusname, $textname) {
  let $info := ectei:get-text-info($corpusname, $textname)
  return
    if (count($info)) then
      $info
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

(:~
 : Add new or update existing TEI document
 :
 : When sending a PUT request to a new text URI, the request body is stored in
 : the database as a new document accessible under that URI. If the URI already
 : exists the corresponding TEI document is updated with the request body.
 :
 : The `textname` parameter of a new URI must consist of lower case ASCII
 : characters, digits and/or dashes only.
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @param $data TEI document
 : @param $auth Authorization header value
 : @result updated TEI document
 :)
declare
  %rest:PUT("{$data}")
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:consumes("application/xml", "text/xml")
  %output:method("xml")
function api:text-tei-put($corpusname, $textname, $data, $auth) {
  if (not($auth)) then
    <rest:response>
      <http:response status="401"/>
    </rest:response>
  else

  let $corpus := ectei:get-corpus($corpusname)
  let $doc := ecutil:get-doc($corpusname, $textname)

  return
    if (not($corpus)) then
      (
        <rest:response>
          <http:response status="404"/>
        </rest:response>,
        <message>No such corpus</message>
      )
    else if (
      not($doc) and
      not(matches($textname, "^[a-z0-9]+(-?[a-z0-9]+)*$"))
    )
    then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        <message>Unacceptable text name '{$textname}'. Use lower case ASCII characters, digits and dashes only.</message>
      )
    else if (not($data/tei:TEI)) then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        <message>TEI document required</message>
      )
    else
      let $filename := $textname || ".xml"
      let $collection := $config:data-root || "/" || $corpusname
      let $result := xmldb:store($collection, $filename, $data/tei:TEI)
      return $data
};

(:~
 : Remove a single text from the corpus
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @param $auth Authorization header value
 : @result JSON object
 :)
declare
  %rest:DELETE
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}")
  %rest:header-param("Authorization", "{$auth}")
  %output:method("json")
function api:text-delete($corpusname, $textname, $data, $auth) {
  if (not($auth)) then
    <rest:response>
      <http:response status="401"/>
    </rest:response>
  else

  let $doc := ecutil:get-doc($corpusname, $textname)

  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $filename := $textname || ".xml"
      let $collection := $config:data-root || "/" || $corpusname
      return (xmldb:remove($collection, $filename))
};

(:~
 : Get TEI document for a single text
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @result XML document
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}/tei")
  %rest:produces("application/xml")
  %output:media-type("application/xml")
  %output:method("xml")
function api:text-tei($corpusname, $textname) {
  let $doc := ecutil:get-doc($corpusname, $textname)
  return
    if (count($doc)) then
      $doc/tei:TEI
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

(:~
 : Get segments for a single text
 :
 : This provides a JSON object that can serve as payload for the extractor
 : service.
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}/segments")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:text-segments($corpusname, $textname) {
  let $doc := ecutil:get-doc($corpusname, $textname)
  return
    if (count($doc)) then
      entities:segment($doc/tei:TEI)
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};
