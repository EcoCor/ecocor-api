xquery version "1.0";

import module namespace xdb="http://exist-db.org/xquery/xmldb";
import module namespace config="http://ecocor.org/ns/exist/config"
  at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)

(: file path pointing to the exist installation directory :)
declare variable $home external;
(: path to the directory containing the unpacked .xar package :)
declare variable $dir external;
(: the target collection into which the app is deployed :)
declare variable $target external;

declare function local:mkcol-recursive($collection, $components) {
    if (exists($components)) then
        let $newColl := concat($collection, "/", $components[1])
        return (
            xdb:create-collection($collection, $components[1]),
            local:mkcol-recursive($newColl, subsequence($components, 2))
        )
    else
        ()
};

(: Helper function to recursively create a collection hierarchy. :)
declare function local:mkcol($collection, $path) {
    local:mkcol-recursive($collection, tokenize($path, "/"))
};

(: store the collection configuration :)
local:mkcol("/db/system/config", $target),
xdb:store-files-from-pattern(
  concat("/db/system/config", $target), $dir, "collection.xconf"
),
xdb:create-collection("/", $config:corpora-root),
xdb:create-collection("/", $config:webhook-root),
local:mkcol("/db/system/config", $config:corpora-root),
xdb:store-files-from-pattern(
  concat("/db/system/config", $config:corpora-root), $dir, "data.xconf"
),
(: Ensure xqsuite unit-tests collection exists under the app root so
 : VS Code's eXist-db sync can push *.xqm files into it without a
 : "collection not found" race on fresh setups. :)
xdb:create-collection($target, "unit-tests"),
xdb:create-collection(concat($target, "/unit-tests"), "fixtures")
