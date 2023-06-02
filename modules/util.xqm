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
  let $corpusname := $segments[last() - 1]
  let $filename := $segments[last()]
  let $textname := substring-before($filename, ".xml")
  return map {
    "filename": $filename,
    "textname": $textname,
    "corpusname": $corpusname,
    "collections": map {
      (: "metrics": $config:metrics-root || "/" || $corpusname, :)
      "entities": $config:entities-root || "/" || $corpusname,
      "tei": $config:data-root || "/" || $corpusname
    },
    "files": map {
      "tei": $config:data-root || "/" || $corpusname || "/" || $filename
    },
    "url": $url
  }
};

(:~
 : Return document for a text.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function ecutil:get-doc(
  $corpusname as xs:string,
  $textname as xs:string
) as node()* {
  let $doc := doc(
    $config:data-root || "/" || $corpusname || "/" || $textname || ".xml"
  )
  return $doc
};

(:~
 : Return documents in a corpus.
 :
 : @param $corpusname
 :)
declare function ecutil:get-corpus-docs(
  $corpusname as xs:string
) as node()* {
  let $collection := concat($config:data-root, "/", $corpusname)
  let $col := collection($collection)
  return $col//tei:TEI
};
