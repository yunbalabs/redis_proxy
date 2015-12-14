# redis_proxy

An Erlang proxy for redis. It's based on [distributed_proxy](https://github.com/yunbalabs/distributed_proxy).

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