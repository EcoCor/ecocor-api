xquery version "3.1";

(:~
 : A set of helper functions to access the application context from
 : within a module.
 :)
module namespace config="http://ecocor.org/ns/exist/config";

declare namespace templates="http://exist-db.org/xquery/templates";
declare namespace repo="http://exist-db.org/xquery/repo";
declare namespace expath="http://expath.org/ns/pkg";

(:
    Determine the application root collection from the current module load path.
:)
declare variable $config:app-root :=
    let $rawPath := system:get-module-load-path()
    let $modulePath :=
        (: strip the xmldb: part :)
        if (starts-with($rawPath, "xmldb:exist://")) then
            if (starts-with($rawPath, "xmldb:exist://embedded-eXist-server")) then
                substring($rawPath, 36)
            else if (starts-with($rawPath, "xmldb:exist://null")) then
                substring($rawPath, 19)
            else
                substring($rawPath, 15)
        else
            $rawPath
    return
        substring-before($modulePath, "/modules")
;

declare variable $config:ecocor-root := "/db/ecocor";
declare variable $config:corpora-root := $config:ecocor-root || "/corpora";
declare variable $config:webhook-root := $config:ecocor-root || "/webhook";

declare variable $config:file := $config:ecocor-root || "/config.xml";
declare variable $config:secrets-file := $config:ecocor-root || "/secrets.xml";

(:
  The base URL under which the REST API is hosted.

  FIXME: This should be determined dynamically using request:get-*() functions.
  However the request object doesn't seem to be available in a RESTXQ context.
:)
declare variable $config:api-base :=
  doc($config:file)//api-base/normalize-space();

declare variable $config:webhook-secret :=
  doc($config:secrets-file)//gh-webhook/normalize-space();

(: the directory path in corpus repos where the TEI files reside :)
declare variable $config:corpus-repo-prefix := 'tei';

declare variable $config:repo-descriptor :=
  doc(concat($config:app-root, "/repo.xml"))/repo:meta;

declare variable $config:expath-descriptor :=
  doc(concat($config:app-root, "/expath-pkg.xml"))/expath:package;

declare variable $config:extractor-server :=
  xs:anyURI(
    doc($config:file)//services/extractor/normalize-space()
  );

(:~
 : Resolve the given path using the current application context.
 : If the app resides in the file system,
 :)
declare function config:resolve($relPath as xs:string) {
    if (starts-with($config:app-root, "/db")) then
        doc(concat($config:app-root, "/", $relPath))
    else
        doc(concat("file://", $config:app-root, "/", $relPath))
};

(:~
 : Returns the repo.xml descriptor for the current application.
 :)
declare function config:repo-descriptor() as element(repo:meta) {
    $config:repo-descriptor
};

(:~
 : Returns the expath-pkg.xml descriptor for the current application.
 :)
declare function config:expath-descriptor() as element(expath:package) {
    $config:expath-descriptor
};
