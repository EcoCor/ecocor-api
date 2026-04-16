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
 : API base
 :
 : Shows version numbers of the ecocor-api app and the underlying eXist-db.
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/ecocor")
  %rest:produces("application/json")
  %output:method("json")
function api:base() {
  let $expath := config:expath-descriptor()
  let $repo := config:repo-descriptor()
  return map {
    "name": $expath/expath:title/string(),
    "version": $expath/@version/string(),
    "existdb": system:get-version(),
    "base": $config:api-base
  }
};

(:~
 : API info
 :
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
  api:base()
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
    for $corpus in collection($config:corpora-root)//tei:teiCorpus
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

  let $header := if ($data) then $data//tei:teiCorpus/tei:teiHeader else ()
  let $name := $header//tei:publicationStmt/tei:idno[not(@type)][1]/text()

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
      ecutil:create-corpus($name, $data/tei:teiCorpus),
      map {
        "name": $name,
        "title": $title
      }
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
  %rest:header-param("Authorization", "{$auth}")
  %rest:consumes("application/json")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora-post-json($data, $auth) {
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
  else (
    ecutil:create-corpus($json),
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
  let $collection := concat($config:corpora-root, "/", $corpusname)
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
 : Update corpus.xml
 :
 : Sending a PUT request to the corpus URI updates the corpus.xml file of the
 : corpus with the payload. This endpoint requires authorization.
 :
 : @param $corpusname Corpus name
 : @param $auth Authorization header value
 : @result JSON object
 :)
declare
  %rest:PUT("{$data}")
  %rest:path("/ecocor/corpora/{$corpusname}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:consumes("application/xml", "text/xml")
  %output:method("json")
function api:put-corpus($corpusname, $data, $auth) {
  if (not($auth)) then
    (
      <rest:response>
        <http:response status="401"/>
      </rest:response>,
      map {
        "error": "authorization required"
      }
    )
  else

  let $corpus := ectei:get-corpus($corpusname)

  return
    if (not($corpus)) then
      (
        <rest:response>
          <http:response status="404"/>
        </rest:response>,
        map {
          "error": "No such corpus"
        }
      )
    else if (not($data/tei:teiCorpus)) then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        map {
          "error": "teiCorpus document required"
        }
      )
    else if (
      not(
        $data/tei:teiCorpus/tei:teiHeader/tei:fileDesc/tei:publicationStmt
          /tei:idno[not(@type)][1] eq $corpusname
      )
    )
    then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        map {
          "error": "Corpus name mismatch",
          "message": "The corpus name in the payload differs from the one in the resource path."
        }
      )
    else
      let $collection := $config:corpora-root || "/" || $corpusname
      let $result := xmldb:store($collection, "corpus.xml", $data/tei:teiCorpus)
      let $newCorpus := ectei:get-corpus-info-by-name($corpusname)
      return $newCorpus
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
      let $url := $config:corpora-root || "/" || $corpusname || "/corpus.xml"
      return
        if ($url = $corpus/base-uri()) then
        (
          xmldb:remove($config:corpora-root || "/" || $corpusname),
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
  let $collection := concat($config:corpora-root, "/", $corpusname)
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
  let $collection := concat($config:corpora-root, "/", $corpusname)
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
      let $collection := xmldb:create-collection(
        $config:corpora-root || "/" || $corpusname, $textname
      )
      let $result := xmldb:store($collection, "tei.xml", $data/tei:TEI)
      let $_ := (
        ecutil:remove-corpus-sha($corpusname),
        ecutil:remove-sha($corpusname, $playname)
      )
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

  let $paths := ecutil:filepaths($corpusname, $textname)

  return
    if (not(doc($paths?files?tei))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      ecutil:remove-corpus-sha($corpusname),
      xmldb:remove($paths?collections?text)
};

(:~
 : Get entities for a single text
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @result JSON object with entities data
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}/entities")
  %rest:query-param("type", "{$type}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:text-entities($corpusname, $textname, $type) {
  let $entities := entities:text($corpusname, $textname, $type)
  return
    if (count($entities)) then
      $entities
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

(:~
 : Get entities for a single text as CSV
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @result Entities CSV
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}/entities/csv")
  %rest:query-param("type", "{$type}")
  %rest:produces("text/csv")
  %output:media-type("text/csv")
  %output:method("text")
function api:text-entities-csv($corpusname, $textname, $type) {
  let $entities := entities:text-csv($corpusname, $textname, $type)
  return
    if (count($entities)) then
      $entities
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
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
 : Get plain text version of a single text
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @result Plain text document
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}/plaintext")
  %rest:produces("text/plain")
  %output:media-type("text/plain")
  %output:method("text")
function api:text-plain($corpusname, $textname) {
  let $doc := ecutil:get-doc($corpusname, $textname)
  return
    if (count($doc)) then
      ectei:get-plain-text($corpusname, $textname)
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

(:~
 : List all tokens (<w> and <pc>) of a text
 :
 : Source: {text}/tokenized.xml. Returns 404 if that document is missing.
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @param $format Output format: "json" (default) or "tsv"
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}/tokens")
  %rest:query-param("format", "{$format}", "json")
function api:text-tokens($corpusname, $textname, $format) {
  let $paths := ecutil:filepaths($corpusname, $textname)
  let $tokenized-file := $paths?collections?text || "/tokenized.xml"
  let $tokenized := if (doc-available($tokenized-file)) then doc($tokenized-file) else ()

  return
    if (not($tokenized)) then (
      <rest:response><http:response status="404"/></rest:response>,
      map {
        "error": "tokenized TEI not found",
        "message": "No tokenized.xml for text '" || $textname
          || "' in corpus '" || $corpusname
          || "'. This endpoint requires a tokenized TEI (with <w>/<pc> elements) alongside the base tei.xml."
      }
    )
    else
      let $tokens := $tokenized//tei:text//(tei:w|tei:pc)
      return if ($format = "tsv") then
        let $header := string-join(("id", "text", "type"), "&#9;")
        let $rows :=
          for $token in $tokens
          return string-join((
            string($token/@xml:id),
            string($token),
            local-name($token)
          ), "&#9;")
        return (
          <rest:response>
            <http:response status="200">
              <http:header name="Content-Type" value="text/tab-separated-values; charset=utf-8"/>
            </http:response>
          </rest:response>,
          string-join(($header, $rows), "&#10;")
        )
      else (
        <rest:response>
          <http:response status="200">
            <http:header name="Content-Type" value="application/json"/>
          </http:response>
        </rest:response>,
        serialize(
          array {
            for $token in $tokens
            return map:merge((
              map {
                "id": string($token/@xml:id),
                "text": string($token),
                "type": local-name($token)
              },
              if ($token/@unit) then map:entry("unit", string($token/@unit)) else ()
            ))
          },
          map { "method": "json" }
        )
      )
};

(:~
 : Get a single token with all annotations
 :
 : Looks up the token in tokenized.xml by xml:id and aggregates all
 : annotations targeting it across every layer in annotations/. The
 : annotations array is flat; each entry carries its layer name.
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @param $tokenid Token xml:id
 :)
declare
  %rest:GET
  %rest:path("/ecocor/corpora/{$corpusname}/texts/{$textname}/tokens/{$tokenid}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:text-token($corpusname, $textname, $tokenid) {
  let $paths := ecutil:filepaths($corpusname, $textname)
  let $tokenized-file := $paths?collections?text || "/tokenized.xml"
  let $tokenized := if (doc-available($tokenized-file)) then doc($tokenized-file) else ()
  let $token :=
    if ($tokenized) then
      $tokenized//(tei:w|tei:pc)[@xml:id = $tokenid]
    else ()

  return
    if (not($tokenized)) then (
      <rest:response><http:response status="404"/></rest:response>,
      map {
        "error": "tokenized TEI not found",
        "message": "No tokenized.xml for text '" || $textname
          || "' in corpus '" || $corpusname || "'."
      }
    )
    else if (not($token)) then (
      <rest:response><http:response status="404"/></rest:response>,
      map {
        "error": "token not found",
        "message": "No <w> or <pc> element with xml:id='" || $tokenid
          || "' in text '" || $textname || "'."
      }
    )
    else
      let $ann-collection := $paths?collections?text || "/annotations"
      let $target-ref := "#" || $tokenid
      return map:merge((
        map {
          "id": $tokenid,
          "text": string($token),
          "type": local-name($token)
        },
        if ($token/@unit) then map:entry("unit", string($token/@unit)) else (),
        if (xmldb:collection-available($ann-collection)) then
          map:entry("annotations", array {
            for $resource in xmldb:get-child-resources($ann-collection)
            let $doc := doc($ann-collection || "/" || $resource)
            let $layername := replace($resource, '\.xml$', '')
            for $a in $doc//tei:annotation[
              tokenize(@target, '\s+') = $target-ref
            ]
            return map {
              "layer": $layername,
              "body": array {
                for $attr in $a/(@ana, @corresp)
                return map {
                  "key": local-name($attr),
                  "value": string($attr)
                },
                for $note in $a/tei:note[@type]
                return map {
                  "key": string($note/@type),
                  "value": normalize-space($note)
                }
              }
            }
          })
        else ()
      ))
};
