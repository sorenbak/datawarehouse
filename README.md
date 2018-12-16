# datawarehouse
DW - Control Input and Output

## Background

A common pitfall encountered when implementing a new system in a large
organisation is to ignore the data flows right from the
beginning. Data enters the new system database from various channels
and nobody seems to know where the initial set actually came from or
how the live system is actually updated. Data - and test data in
particula - is mystified and tests are performed on "golden master"
datasets, which again are entangled in production data.

Installing a datawarehouse responsible for managing incoming data with
tracability to the origin - down to every single value - can be a good
starting point. Every incoming dataset is then received, tracked,
uploaded, validated, transformed and published to the new system in a
structured (ETL) process to ensure accountability and allow system
managers to "protect" the new system from the sometimes hostile
environment in a company's data streams.

This datawarehouse is a fairly simple solution built throughout around
the concept of _agreements_ defining each dataset - what it looks like
from the origin and how it is transformed into validated and
production ready data. An incoming dataset could be CSV file with a
number of columns which needs to be loaded into the datawarehouse and
validated against dimension tables, defining valid values on certain
columns, check the content types (number, date, etc) or if values
follow specific predefined patterns. All this needs to pass
successfully before the data is transformed into destination tables
and published for consumption.

##History

The initial solution was initiated in 2006 and was based on ideas from
a course in Datawarehouse ETL processes, which was a relatively new
concept at the time. The results was a running solution in PostgreSQL,
which was open sourced around 2007 and later in 2010 migrated to MS
SQL Server for other client needs. The project was abandoned for a few
years due to inactivity and removed from the net, until recently time
and resources allowed for a refactor into Azure SQL Server and move
from private hosting to github.

# Setup

Download the `sql-migrate` tool (see [here for
details](https://github.com/rubenv/sql-migrate)):
````
go get -v github.com/rubenv/sql-migrate/...
````

Please edit settings below according to your own needs

## Create database

You need to connect to the `master` database to perform this task
````
CREATE DATABASE datawarehouse
````

## Create login/user

Connect to the newly database created (`datawarehouse`)
````
CREATE LOGIN qwert WITH PASSWORD = 'Qwerty12#¤'

CREATE USER [qwert] FOR LOGIN [qwert] WITH DEFAULT_SCHEMA=[dbo]
GO
-- Overkill
ALTER ROLE [db_owner] ADD MEMBER [qwert]
GO
````

## Create `dbconfig.yml` file based on your choices
````
development:
    dialect: mssql
    datasource: server=localhost;database=datawarehouse;user id=qwert;password=Qwerty12#¤
    dir: mssql/migrations
    table: _migrations
````

## Migrate up
````
sql-migrate up
````

## Build the frontend (incl swagger GUI)

````
go build
go generate
````

## Setup `.env`

````
DBCONNECTIONSTRING=server=localhost;database=datawarehouse;user id=qwert;password=Qwerty12#¤
HTTPADDR=:8080
````

To use authentication (with Azure tenant), add

````
USEAUTH=yes
TENANTID=yourdomain.onmicrosoft.com
````

Alternatively use a secret of your own and create authentication
tokens yourself (e.g. via [JWT](https://jwt.io/))

````
USEAUTH=yes
JWTSECRET=mysecret
````

To enable SSL (https)

````
USESSL=yes
HTTPSADDR=:443
HTTPSFQN=www.yourdomain.com
HTTPSEMAIL=somebody@yourdomain.com
````
