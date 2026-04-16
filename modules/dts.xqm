xquery version "3.1";

(:~
 : Distributed Text Services (DTS) v1.0 API for EcoCor.
 :
 : Implements the four endpoints defined in
 : https://dtsapi.org/specifications/versions/v1.0/
 :
 :   - Entry Point  (GET /dts)
 :   - Collection   (GET /dts/collection{?id,page,nav})
 :   - Navigation   (GET /dts/navigation{?resource,ref,start,end,down,tree,page})
 :   - Document     (GET /dts/document{?resource,ref,start,end,tree,mediaType})
 :
 : The module prefix is `ecdts` because `dts` is reserved as the XML
 : namespace used in Document-endpoint responses (`<dts:wrapper>`).
 :)
module namespace ecdts = "http://ecocor.org/ns/exist/dts";

import module namespace config = "http://ecocor.org/ns/exist/config"
  at "config.xqm";
import module namespace ectei = "http://ecocor.org/ns/exist/tei"
  at "tei.xqm";
import module namespace ecutil = "http://ecocor.org/ns/exist/util"
  at "util.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace dts = "https://dtsapi.org/v1.0#";

(: Non-negotiable constants from the spec :)
declare variable $ecdts:spec-version := "1.0";
declare variable $ecdts:jsonld-context := "https://dtsapi.org/context/v1.0.json";

(: Base URLs for the four endpoints :)
declare variable $ecdts:api-base := $config:api-base || "/dts";
declare variable $ecdts:collection-base := $ecdts:api-base || "/collection";
declare variable $ecdts:navigation-base := $ecdts:api-base || "/navigation";
declare variable $ecdts:document-base := $ecdts:api-base || "/document";

(:~
 : Entry Point — advertises the URI templates for the other three
 : endpoints so clients can discover them.
 :
 : Spec: https://dtsapi.org/specifications/versions/v1.0/#entry-endpoint
 :)
declare
  %rest:GET
  %rest:path("/ecocor/dts")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ecdts:entry-point() {
  map {
    "@context": $ecdts:jsonld-context,
    "@id": $ecdts:api-base,
    "@type": "EntryPoint",
    "dtsVersion": $ecdts:spec-version,
    "collection": $ecdts:collection-base || "{?id,page,nav}",
    "navigation": $ecdts:navigation-base
      || "{?resource,ref,start,end,down,tree,page}",
    "document": $ecdts:document-base
      || "{?resource,ref,start,end,tree,mediaType}"
  }
};
