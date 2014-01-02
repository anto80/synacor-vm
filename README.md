SynacorVm
==========

Synacor VM Challenge  https://challenge.synacor.com/


== Synacor Challenge ==
-----------------------

  In this challenge, your job is to use this architecture spec to create a
  virtual machine capable of running the included binary.  Along the way,
  you will find codes; submit these to the challenge website to track
  your progress.  Good luck! ...

Environment
-------------------
I've resolved this challenge using Lua scripting language embedded in REDIS.
I'm not a Lua developer but i'm a redis fan ;)

Running
-------

warning : This command has only been tested on OSX

	redis-cli set "synacor_challenge:bin" "$(od -d -An challenge.bin | xargs)" && redis-cli EVAL "$(cat vm.lua)" 0 input1 input2 .. | xargs -0 echo
	
	
	
[![Analytics](https://ga-beacon.appspot.com/UA-46796078-1/synacor-vm)](https://github.com/anto80/synacor-vm)

