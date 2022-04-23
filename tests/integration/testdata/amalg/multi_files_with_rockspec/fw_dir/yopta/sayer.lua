local sayer = {}

function sayer.say_each(n, word)
    for i = 1, n do
        sayer.say(word)
    end
end

function sayer.say(word)
    print(word)
end

return sayer
