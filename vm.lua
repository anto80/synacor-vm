--== Synacor Challenge ==
-- In this challenge, your job is to use this architecture spec to create a
-- virtual machine capable of running the included binary.  Along the way,
-- you will find codes; submit these to the challenge website to track
-- your progress.  Good luck! 

		-----------------------------------------------------
		---- more info at https://challenge.synacor.com/ ----
		-----------------------------------------------------

---------------------------------- RUNNING ------------------------------------

--redis-cli set "synacor_challenge:bin" "$(od -d -An challenge.bin | xargs)" &&
--  redis-cli EVAL "$(cat vm.lua)" 0 input1 input2 .. | xargs -0 echo

-------------------------------------------------------------------------------


--==**** FOR YOUR ENJOY OPEN REDIS MONITOR DURING THE RUNNING ****==--


local ns = 'synacor_challenge:'
local binaryPipe = 'bin'
local mem = 'memory'
local registers = 'registers' 
local stack = 'stack'
local mcursor = 0

local stackError = nil
local prompt = nil
local inputStr = ''

-- Opcode table
local opcode = { 
	function(scope) -- HALT
		return redis.call('GET', ns .. 'buffer') 
	end, 
	function(scope) -- SET
		local par = scope.gP(2)
		redis.call('HSET', ns .. registers , par[1], scope.grv(par[2]))
	end,
	function(scope)  -- PUSH
		 local par = scope.gP(1)
		 redis.call('LPUSH', ns .. stack, scope.grv(par[1]))
	end, 
	function(scope) -- POP
		local par = scope.gP(1)
		local v = redis.call('LPOP', ns .. stack)
		if v == nil then
			stackError = true
		end
		redis.call('HSET', ns .. registers , par[1], scope.grv(v))
	end,  
	function(scope)  -- EQ
		local par = scope.gP(3)
		local result = 0
		if scope.grv(par[2]) == scope.grv(par[3]) then
			result = 1
		end
		redis.call('HSET', ns .. registers , par[1], result) 
	end, 
	function(scope)  -- GT
		local par = scope.gP(3)
		local result = 0
		if scope.grv(par[2]) > scope.grv(par[3]) then
			result = 1
		end
		redis.call('HSET', ns .. registers , par[1], result) 
	end, 
	function(scope)  -- JMP
		local par = scope.gP(1)
		mcursor = scope.grv(par[1]) -1
	end, 
	function(scope)  -- JT
		local par = scope.gP(2)
		if scope.grv(par[1]) ~= 0 then
			mcursor = scope.grv(par[2]) -1
		end
	end, 
	function(scope) -- JF
		local par = scope.gP(2)
		if scope.grv(par[1]) == 0 then
			mcursor = scope.grv(par[2]) -1
		end
	end,  
	function(scope) -- ADD
		local par = scope.gP(3)
		redis.call('HSET', 
			ns .. registers , 
			par[1], 
			math.fmod(
				scope.grv(par[2]) + scope.grv(par[3]), 32768 
			)
		) 
	end,  
	function(scope) -- MULT
		local par = scope.gP(3)
		redis.call(
			'HSET', 
			ns .. registers , 
			par[1], 
			math.fmod(scope.grv(par[2]) * scope.grv(par[3]), 32768 )
		) 
	end,  
	function(scope)  -- MOD
		local par = scope.gP(3)
		redis.call(
			'HSET', 
			ns .. registers , 
			par[1], 
			math.fmod (scope.grv(par[2]), scope.grv(par[3]))
		) 
	end, 
	function(scope)  -- AND
		local par = scope.gP(3)
		local bitop = scope.bitwise(
			scope.grv(par[2]), 
			scope.grv(par[3]), 
			'AND', 
			scope
		)
		redis.call('HSET', ns .. registers , par[1],  bitop ) 
	end, 
	function(scope)  -- OR
		local par = scope.gP(3)
		local bitop = scope.bitwise(
			scope.grv(par[2]), 
			scope.grv(par[3]), 
			'OR', 
			scope
		)
		redis.call('HSET', ns .. registers , par[1],  bitop ) 
	end, 
	function(scope) -- NOT
		local par = scope.gP(2)
		local bitop = scope.bitwise(scope.grv(par[2]), nil, 'NOT', scope)
		redis.call('HSET', ns .. registers , par[1],  bitop ) 
	end,  
	function(scope) -- RMEM
		local par = scope.gP(2)
		local seek = scope.grv(par[2])
		local read = redis.call('LRANGE', ns .. mem, seek, seek) 
		redis.call('HSET', ns .. registers , par[1], tonumber(read[1])) 
	end,  
	function(scope) -- WMEM
		local par = scope.gP(2)
		redis.call('LSET', ns .. mem, scope.grv(par[1]),  scope.grv(par[2]))
	end,  
	function(scope)  -- CALL
		local par = scope.gP(1)
		redis.call('LPUSH', ns .. stack, mcursor+1)
		mcursor = scope.grv(par[1]) -1
	end, 
	function(scope)  -- RET
		local val = redis.call('LPOP', ns .. stack)
		mcursor = tonumber(val) -1
	end, 
	function(scope)  -- OUT
		local par = scope.gP(1)  
		redis.call('APPEND', ns .. 'buffer', string.char(scope.grv(par[1])) )
	end, 
	function(scope)  -- IN
		local par = scope.gP(1) 
		if redis.call('LLEN',  ns .. 'inputAsChar') == 0 then
			prompt = true
			redis.log(redis.LOG_WARNING,'prompt') 
			return
		end
		local inputChar = redis.call('LPOP', ns .. 'inputAsChar')
		redis.call('HSET', ns .. registers , par[1], inputChar) 
		redis.call('APPEND', ns .. 'buffer', string.char(inputChar))	
	end, 
	function(scope) return end  -- NOOP
}


-- reset
local reset = function() 
	
	redis.call('DEL', ns .. mem)	
	redis.call('DEL', ns .. registers)
	redis.call('DEL', ns .. stack)
	
	redis.call('DEL', ns .. 'input')
	redis.call('DEL', ns .. 'buffer')

	redis.call('DEL', ns .. 'inputAsChar')
	redis.call('DEL', ns .. 'input')

	-- init registers
 	for reg = 32768, 32775, 1 do 
 		redis.call('HSET', ns .. registers , reg , 0)
 	end

end



----------------------------------------
-- "malloc" and copy opcode to memory --
----------------------------------------
local copy2Mem = function() 
	local tmpMem = string.gsub(redis.call('GET', ns..binaryPipe), "\n", " ")
    tmpMem:gsub("([^".." ".."]*)".." ", 
    	function(d) 
    		redis.call('RPUSH', ns .. mem, d) 
    	end
    )
    -- fill the memory
	for index = tonumber(redis.call('LLEN', ns .. mem)) - 1 , 32767, 1 do 
		redis.call('RPUSH', ns .. mem , 0)
	end
end


-- Get Parameters
local gP = function(n) 
	local result = redis.call('LRANGE', ns..mem, mcursor + 1, mcursor + n + 1)
	mcursor = mcursor + n
	return result
end



-- Get real value of parameter
local grv = function(v)
	local v = tonumber(v)
	if v >= 32768 and v <= 32775 then
		return tonumber(redis.call('HGET', ns .. registers , v))
	end
	return v
end


---------------------------------------------------------------
-- Bitwise operation are not allowed in this Lua environment --
-- and Redis BITOP NOT is bugged in redis:2.6.16             --
-- so ... roll up my sleeves                                 --
---------------------------------------------------------------

local toBits = function(num, scope)
  
  	if num == nil then
  		num = 0
  	end

    local t={} -- will contain the bits
    local rest = 0
    while num>0 do
        rest=math.fmod(num,2)
        t[#t+1]=rest
        num=(num-rest)/2
    end
    local reverseTable = {}
    local nI = 0
    for i=16, 1, -1 do
        if t[i] ~= nil then  
           reverseTable[nI] = t[i]
        else
          reverseTable[nI] = 0
        end
        nI = nI + 1
    end
    return reverseTable
end


local bitwise = function(num1, num2, oper, scope)
    
    local result = {}
    local n1T = scope.toBits(num1)
    local n2T = scope.toBits(num2)
    
    for i=1, 16, 1 do
        
        if oper == 'AND' then
          if n1T[i] == 1 and n2T[i] == 1 then
            result[i] = 1
          elseif n1T[i] == 0 or n2T[i] == 0 then
             result[i] = 0
          end  
        end
        
        if oper == 'OR' then
          if n1T[i] == 1 or n2T[i] == 1 then
            result[i] = 1
          elseif n1T[i] == 0 and n2T[i] == 0 then
             result[i] = 0
          end  
        end
        
        if oper == 'NOT' then
          if n1T[i] == 1  then
             result[i] = 0
          elseif n1T[i] == 0 then
            result[i] = 1
          end
        end 
    end
    return tonumber(table.concat(result), 2)
end



-- MAIN function
local main = function()
	
	reset()
	copy2Mem()

	local scope = {
		gP = gP,
		grv = grv,
		toBits = toBits,
		bitwise = bitwise
	}

	local res = ''
	
	-- init input paramenter
 	for i=1, #ARGV, 1 do
 		redis.call('RPUSH', ns .. 'input', ARGV[i])
 		inputStr = inputStr .. ARGV[i] .. '\n'
 	end
 	
 	inputStr:gsub(".", function(c)
 		redis.call('RPUSH', ns .. 'inputAsChar', string.byte(c))
	end)
 	
	while true do
    
    	local v = redis.call('LRANGE', ns .. mem, mcursor, mcursor)
    	
    	if opcode[tonumber(v[1])+1] ~= nil then
    		res = opcode[tonumber(v[1])+1](scope)
    	end

    	mcursor = mcursor + 1    	
    	redis.call('SET', ns .. 'cursor', mcursor) 

    	if tonumber(v[1]) == 0 then
    		return res
    	end

    	if stackError ~= nil then
    		return 'error : Stack is empty'
    	end

    	if prompt ~= nil then
    		return redis.call('GET', ns .. 'buffer') 
    	end

    end
	return 1
end


return main()


