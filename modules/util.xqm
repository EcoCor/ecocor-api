xquery version "3.1";

(:~
 : Module providing utility functions for EcoCor API.
 :)
module namespace ecutil = "http://ecocor.org/ns/exist/util";

import module namespace config = "http://ecocor.org/ns/exist/config" at "config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace json = "http://www.w3.org/2013/XSL/json";

(:~
 : Provide map of files and paths related to a text.
 :
 : @param $url DB URL to text TEI document
 : @return map()
 :)
declare function ecutil:filepaths ($url as xs:string) as map() {
  let $segments := tokenize($url, "/")
  let $corpusname := $segments[last() - 2]
  let $textname := $segments[last() - 1]
  let $filename := $segments[last()]
  return ecutil:filepaths($corpusname, $textname, $filename)
};

(:~
 : Provide map of files and paths related to a text.
 :
 : @param $corpusname
 : @param $textname
 : @return map()
 :)
declare function ecutil:filepaths (
  $corpusname as xs:string,
  $textname as xs:string
) as map() {
  ecutil:filepaths($corpusname, $textname, "tei.xml")
};

(:~
 : Provide map of files and paths related to a text.
 :
 : @param $corpusname
 : @param $textname
 : @param $filename
 : @return map()
 :)
declare function ecutil:filepaths (
  $corpusname as xs:string,
  $textname as xs:string,
  $filename as xs:string
) as map() {
  let $textpath := $config:corpora-root || "/" || $corpusname || "/" || $textname
  let $url := $textpath || "/" || $filename
  let $uri :=
    $config:api-base || "/corpora/" || $corpusname || "/texts/" || $textname
  return map {
    "uri": $uri,
    "url": $url,
    "filename": $filename,
    "textname": $textname,
    "corpusname": $corpusname,
    "collections": map {
      "corpus": $config:corpora-root || "/" || $corpusname,
      "text": $textpath
    },
    "files": map {
      "tei": $textpath || "/tei.xml",
      "metrics": $textpath || "/metrics.xml",
      "entities": $textpath || "/entities.xml",
      "git": $textpath || "/git.xml"
    }
  }
};

(:~
 : Return document for an individual text.
 :
 : @param $corpusname
 : @param $textname
 : @param $root Path to root directory
 :)
declare function ecutil:get-doc(
  $corpusname as xs:string,
  $textname as xs:string,
  $root as xs:string
) as node()* {
  doc($root || "/" || $corpusname || "/" || $textname || "/tei.xml")
};


(:~
 : Return TEI document for an individual text.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function ecutil:get-doc(
  $corpusname as xs:string,
  $textname as xs:string
) as node()* {
  let $paths := ecutil:filepaths($corpusname, $textname)
  return doc($paths?files?tei)
};

(:~
 : Return documents in a corpus.
 :
 : @param $corpusname
 :)
declare function ecutil:get-corpus-docs(
  $corpusname as xs:string
) as node()* {
  let $collection := $config:corpora-root || "/" || $corpusname
  let $col := collection($collection)
  return $col/tei:TEI[not(@type)]
};

(:~
 : Create new corpus collection
 :
 : @param $corpus Map with corpus description
 :)
declare function ecutil:create-corpus($corpus as map()) {
  let $xml :=
    <teiCorpus xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title>{$corpus?title}</title>
          </titleStmt>
          <publicationStmt>
            <idno>{$corpus?name}</idno>
            {
              if ($corpus?repository)
              then <idno type="repo">{$corpus?repository}</idno>
              else ()
            }
          </publicationStmt>
        </fileDesc>
        {if ($corpus?description) then (
          <encodingDesc>
            <projectDesc>
              {
                for $p in tokenize($corpus?description, "&#10;&#10;")
                return <p>{$p}</p>
              }
            </projectDesc>
          </encodingDesc>
        ) else ()}
      </teiHeader>
    </teiCorpus>

  return ecutil:create-corpus($corpus?name, $xml)
};

(:~
 : Create new corpus collection
 :
 : @param $name Corpus name
 : @param $xml Corpus description
 :)
declare function ecutil:create-corpus(
  $name as xs:string,
  $xml as element(tei:teiCorpus)
) {
  if (not($name)) then (
    util:log-system-out("Missing corpus name. Cannot create corpus!")
  ) else (
    util:log-system-out("creating corpus"),
    util:log-system-out($xml),
    xmldb:store(
      xmldb:create-collection($config:corpora-root, $name),
      "corpus.xml",
      $xml
    )
  )
};

(:~
 : Determine Git SHA for corpus recorded in git.xml files
 :
 : @param $name Corpus name
 : @return string* Git SHA1 hash
 :)
declare function ecutil:get-corpus-sha($name as xs:string) as xs:string* {
  let $col := collection($config:corpora-root || "/" || $name)
  let $num-texts := count($col/tei:TEI[not(@type)])
  let $num-sha := count($col/git/sha)
  let $shas := distinct-values($col/git/sha)

  return if($num-texts = $num-sha and count($shas) = 1) then $shas[1] else ()
};

declare function local:record-sha(
  $collection as xs:string,
  $sha as xs:string
) as xs:string* {
  try {
    xmldb:store( $collection, "git.xml", <git><sha>{$sha}</sha></git>)
  } catch * {
    util:log-system-out($err:description)
  }
};

(:~
 : Write commit SHA to git.xml file for text
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 : @return string* Path to git.xml file
 :)
declare function ecutil:record-sha(
  $corpusname as xs:string,
  $textname as xs:string,
  $sha as xs:string
) as xs:string* {
  let $paths := ecutil:filepaths($corpusname, $textname)
  return local:record-sha($paths?collections?text, $sha)
};

(:~
 : Write commit SHA to git.xml file for corpus
 :
 : @param $corpusname Corpus name
 : @return string* Path to git.xml file
 :)
declare function ecutil:record-sha(
  $corpusname as xs:string,
  $sha as xs:string
) as xs:string* {
  let $collection := $config:corpora-root || "/" || $corpusname
  return local:record-sha($collection, $sha)
};

declare function local:remove-sha($collection as xs:string) {
  if (doc-available($collection || "/git.xml")) then (
    util:log-system-out("Removing git.xml for " || $collection),
    xmldb:remove($collection, "git.xml")
  ) else ()
};

(:~
 : Remove corpus git.xml file
 :
 : @param $corpusname Corpus name
 : @return string* Path to git.xml file
 :)
declare function ecutil:remove-corpus-sha(
  $corpusname as xs:string
) as xs:string* {
  let $collection := $config:corpora-root || "/" || $corpusname
  return local:remove-sha($collection)
};

(:~
 : Remove text git.xml file
 :
 : @param $corpusname Corpus name
 : @param $textname Text name
 :)
declare function ecutil:remove-sha(
  $corpusname as xs:string,
  $textname as xs:string
) {
  let $collection :=
    $config:corpora-root || "/" || $corpusname || "/" || $textname
  return local:remove-sha($collection)
};
