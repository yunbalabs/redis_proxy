# redis_proxy

A distributed proxy for redis in Erlang. It's based on [distributed_proxy](https://github.com/yunbalabs/distributed_proxy).

## Usage
### Build
```
$ make generate
```

### Start
```
$ ./rel/redis_proxy/bin/redis_proxy start
```

### Play with redis-cli
```
$ redis-cli -p 6380
127.0.0.1:6380> SET 1 123
OK
127.0.0.1:6380> GET 1
"123"
```

## Supported Commands
### SET key value
```
set 1 1
```

### GET key
```
get 1
```

### MGET key [key ...]
```
mget 1 2 3
```

## Cluster
### Join a cluster
```
$ ./rel/redis_proxy/bin/redis_proxy_admin.sh join any_live_node_in_the_cluster@hostname
```

### Cluster map
```
$ ./rel/redis_proxy/bin/redis_proxy_admin.sh map
```

## Status
### Node status
```
$ ./rel/redis_proxy/bin/redis_proxy_admin.sh status
```

### Replica status
```
$ ./rel/redis_proxy/bin/redis_proxy_admin.sh replicas               %% all replicas status
$ ./rel/redis_proxy/bin/redis_proxy_admin.sh replica replica_id     %% a specific replica status
$ ./rel/redis_proxy/bin/redis_proxy_admin.sh locate key             %% replica status about a specific key
```

### Request/Response status
1. Update config (sys.config).

    - Export stat data through exomter_core
    ```
        %% exometer core config
        {exometer_core, [
            {report, [
                {reporters, [
                    {exometer_report_influxdb, [{protocol, udp},
                        {host, <<"localhost">>},
                        {port, 8089},
                        {db, <<"udp">>}]}
                ]}
            ]}
        ]}
    ```
    - Enable stat
    ```
        {redis_proxy, [
            ...
            {enable_stat, true}
        ]}
    ```

2. Restart the application. The stat data will appear in InfluxDB:

    | measurement name | data type |
    | ---------------- |:-----------------------------:|
    | frontend_request | count of the frontend request |
    | frontend_response| count of the frontend response|
    | backend_request  | count of the backend request  |
    |  latency         | time(milliseconds) of request |

## Benchmark
### Intel(R) Xeon(R) CPU E5-2630 0 @ 2.30GHz, 2300 MHz x 8 + 32G RAM
+ Erlang R16B02

#### slot_num: 1, replica_size: 1
```bash
$ redis-benchmark -t set,get -q -n 10000 -r 10000 -p 6380 -h test.host -c 200
SET: 5293.81 requests per second
GET: 5437.74 requests per second
```

#### slot_num: 8, replica_size: 1
```bash
$ redis-benchmark -t set,get -q -n 100000 -r 100000 -p 6380 -h test.host -c 200
SET: 16742.01 requests per second
GET: 17543.86 requests per second
```

#### slot_num: 16, replica_size: 1
```bash
$ redis-benchmark -t set,get -q -n 100000 -r 100000 -p 6380 -h test.host -c 200
SET: 17006.80 requests per second
GET: 17537.71 requests per second
```

#### slot_num: 32, replica_size: 1
```bash
$ redis-benchmark -t set,get -q -n 100000 -r 100000 -p 6380 -h test.host -c 200
SET: 18653.24 requests per second
GET: 19409.94 requests per second
```

#### slot_num: 64, replica_size: 1
```bash
$ redis-benchmark -t set,get -q -n 100000 -r 100000 -p 6380 -h test.host -c 200
SET: 18145.53 requests per second
GET: 18667.16 requests per second
```

#### slot_num: 32, replica_size: 2
```bash
$ redis-benchmark -t set,get -q -n 100000 -r 100000 -p 6380 -h test.host -c 200
SET: 17247.33 requests per second
GET: 19346.10 requests per second
```

#### slot_num: 1, replica_size: 1, redis_client: eredis_pool
```bash
$ redis-benchmark -t set,get -q -n 100000 -r 100000 -p 6380 -h test.host -c 200
SET: 17479.46 requests per second
GET: 18497.96 requests per second
```

## TODO
### Optimize performance
1. eredis_parser:parse
2. distributed_proxy_util:pmap
3. redis_proxy_util:locate_key
