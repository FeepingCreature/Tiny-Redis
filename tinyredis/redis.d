module tinyredis.redis;

private:
    import std.array : appender;
    import tinyredis.parser : Response, ResponseType;
    
public :
    import tinyredis.connection;
    import tinyredis.parser : encode, RedisResponseException;
    
    class Redis
    {
        private:
            RedisConnection conn;
        
        public:
        
        this(string host = "127.0.0.1", ushort port = 6379)
        {
            conn = new RedisConnection(host, port);
        }
        
        /**
         * Send a request using any type that can be converted to a string
         *
         * send("SADD", "myset", 1)
         * send("SADD", "myset", 1.2)
         * send("SADD", "myset", true)
         * send("SADD", "myset", "Batman")
         * send("SADD", "myset", object) //provided toString is implemented
         * send("GET", "*") == send("GET *")
         */
        R send(R = Response, T...)(string key, T args)
        if(is(R == Response) || Response.canConvert(R))
        {
            return conn.request(encode(key, args))[0];
        }
        
        /**
         * Send a request with a parameterized array. Ex:
         *
         * send("SREM", ["myset", "$3", "$4"]) == send("SREM myset $3 $4")
         */
        Response send(T)(string key, T[] args)
        {
            return conn.request(encode(key, args))[0];
        }
        
        /**
         * Send a redis-encoded string. It can be one or more commands
         */
        Response[] sendRaw(string command)
        {
            return conn.request(command);
        }
        
        /**
         * Send a series of commands as a pipeline
         *
         * pipeline(["SET ctr 1", "INCR ctr", "INCR ctr", "INCR ctr", "INCR ctr"])
         */
        Response[] pipeline(const string[] commands)
        {
            auto app = appender!string();
            foreach(c; commands)
                app.put(encode(c));
            
            return conn.request(app.data);
        }        
        
        private:
        string[] convertToArray(Response response)
        {
            string[] resp;
            foreach(val; response.values)
                resp ~= val.value;
            return resp;
        }
        
        RET convert(RET=Response)(Response response)
        {
            static if(is(RET == bool)) 
            {
                if(response.type == ResponseType.Status)
                    return (response.value == "OK");
                else if(response.type == ResponseType.Integer)
                    return (response.intval == 1);
                else
                    throw new Exception("Cannot convert " ~ response.type ~ " to bool");
            }
            else if(is(RET == int) || is(RET == long) || is(RET == size_t) || is(RET == double))
            {
                if(response.type == ResponseType.Integer)
                    return cast(RET)response.intval;
                else
                    return to!RET(response.value);
            }
            else
                return response;
        }
    }
   
unittest
{
    auto redis = new Redis();
    auto response = redis.send("LASTSAVE");
    assert(response.type == ResponseType.Integer);
    
//    response = redis.send!(bool)("SET", "name", "adil");
    assert(redis.send!(bool)("SET", "name", "adil"));
    
    response = redis.send("GET name");
    assert(response.type == ResponseType.Bulk);
    assert(response.value == "adil");
    
    response = redis.send("GET nonexistentkey");
    assert(response.type == ResponseType.Nil);
    
    redis.send("DEL myset");
    redis.send("SADD", "myset", 1);
    redis.send("SADD", "myset", 1.2);
    redis.send("SADD", "myset", true);
    redis.send("SADD", "myset", "adil");
    redis.send("SADD", "myset", 350001939);
    redis.send("SADD",["myset","$4"]);
    auto r = redis.send("SMEMBERS myset");
    assert(r.type == ResponseType.MultiBulk);
    assert(r.values.length == 6);
    
    redis.send("DEL ctr");
    auto responses = redis.pipeline(["SET ctr 1", "INCR ctr", "INCR ctr", "INCR ctr", "INCR ctr"]);
    
    assert(responses.length == 5);
    assert(responses[0].type == ResponseType.Status);
    assert(responses[1].intval == 2);
    assert(responses[2].intval == 3);
    assert(responses[3].intval == 4);
    assert(responses[4].intval == 5);
}