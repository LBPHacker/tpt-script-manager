A postgresql database with the following extensions enabled is required:

```
create extension citext;
create extension pgcrypto;
```

The following LuaRocks packages are required:

```
luarocks install --lua-version 5.1 --tree=/usr/local lapis
luarocks install --lua-version 5.1 --tree=/usr/local lua-resty-http
luarocks install --lua-version 5.1 --tree=/usr/local lunajson
luarocks install --lua-version 5.1 --tree=/usr/local basexx
luarocks install --lua-version 5.1 --tree=/usr/local lua-resty-jwt
luarocks install --lua-version 5.1 --tree=/usr/local date
```
