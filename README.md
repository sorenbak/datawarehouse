# datawarehouse
DW - Control Input and Output

## Background
A common pitfall encountered when implementing a new system in a large organisation is to ignore the data flows right from the beginning. Data enters the new system database from various channels and nobody seems to know where the initial set actually came from or how the live system is actually updated. Data - and test data in particula - is mystified and tests are performed on "golden master" datasets, which again are entangled in production data. 

Installing a datawarehouse responsible for managing incoming data with tracability to the origin - down to every single value - can be a good starting point. Every incoming dataset is then received, tracked, uploaded, validated, transformed and published to the new system in a structured (ETL) process to ensure accountability and allow system managers to "protect" the new system from the sometimes hostile environment in a company's data streams.

This datawarehouse is a fairly simple solution built throughout around the concept of _agreements_ defining each dataset - what it looks like from the origin and how it is transformed into validated and production ready data. An incoming dataset could be CSV file with a number of columns which needs to be loaded into the datawarehouse and validated against dimension tables, defining valid values on certain columns, check the content types (number, date, etc) or if values follow specific predefined patterns. All this needs to pass successfully before the data is transformed into destination tables and published for consumption.

##History
The initial solution was initiated in 2006 and was based on ideas from a course in Datawarehouse ETL processes, which was a realtively new concept at the time. The results was a running solution in PostgreSQL, which was open sourced around 2007 and later in 2010 migrated to MS SQL Server for other client needs. The project was abandoned for a few years due to inactivity and removed from the host, until recently time and resources allowed for a refactor into Azure SQL Server and move from self hosting to github.
