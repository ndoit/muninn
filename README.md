muninn
======

IMPORTANT NOTE: Like many open-source projects, Muninn started out with a very specific purpose: To front a Neo4j database for use with Notre Dame's data.nd.edu service. It's on its way to being a general-purpose Neo4j ORM layer, but it's nowhere near that yet. It still has a lot of domain-specific stuff, and it's still in development. Many things are hardcoded that really shouldn't be. Much code is in need of cleaning and refactoring. This was my first real Ruby project and it shows. If you want to grab it and bang on it till it suits your needs, go for it, but it's not going to work for you out of the box... yet. A year from now, things will be different - I hope!

Muninn is a front end web service for a Neo4j graph database. Its purpose is to function as an ORM layer. It provides the following:

1. Security. Neo4j is notoriously difficult to secure. By running a local instance and routing all access through Muninn, you can avoid the need for figuring out Neo4j security.
2. Simple CRUD operations using JSON. You can GET, POST, PUT, and DELETE on nodes, while also managing their relationships with other nodes.
3. Built-in search functionality using ElasticSearch. Muninn automatically updates a local ElasticSearch instance with any changes you make to the database.
4. Enforcing a schema. You create a schema for your database, defining node types, relationships, and properties. Muninn enforces this schema on all your CRUD operations.
5. Bulk import and export. You can export your whole database as a JSON array, wipe it, and re-import. If you have data from elsewhere that you want to load, you can do so as long as you can get it into JSON format.

INSTALLATION INSTRUCTIONS
Download Muninn into its own directory.
Install Neo4j on the same computer, running on localhost:7474.
Install ElasticSearch, also on the same computer, running on localhost:9200.
Run Muninn using built-in WEBrick or Unicorn, whatever floats your boat.
