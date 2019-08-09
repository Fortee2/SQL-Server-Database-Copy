# SQL Server Database Copy
SQL and Powershell scripts for exporting a database's structure and data 

## About
Most development is maintaining and enhancing existing systems.  Often times these systems do not have a way to recreate the database structure, but we need these structures to setup local development, testing, and QA environments.   Often times we use backup files and then end up writing script to obfuscate or remove sensitive data.

The purpose of this project is to simplify the process of recreating a SQL Server database structure or being able to script out sections of a database.

## What’s Here?
There are two files that make up this project.  

The first is [Schema.sql](https://github.com/Fortee2/SQL-Serer-Database-Copy/tree/master/ExtractDB/Schema.sql) in the ExtractDB folder.  This script extracts the schema information from your source database using the SQL Server system table and generates the necessary create statements.  

The second file is a Powershell script, [CopyDatabase.ps1](https://github.com/Fortee2/SQL-Serer-Database-Copy/tree/master/Powershell/CopyDatabase.ps1), that executes Schema.sql against the source database and take the output and applies it to a destination database.   The CopyDatabase script also includes calls to the Bulk Copy tool, BCP, to transfer data after the table structure has been created.
