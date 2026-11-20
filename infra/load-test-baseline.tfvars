# Assignment 2 demo configuration, used as the BEFORE run of the load test (docs/load-test.md).
# Expected to fail at the exam peak: tiny instance + every Lambda opening its own connection.
db_instance_class = "db.t4g.micro"
enable_rds_proxy  = false
