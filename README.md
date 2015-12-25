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