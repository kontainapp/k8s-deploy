local t = {'a', 'b', 'c', 'd'}

function indexOf(array, value)
    for i, v in ipairs(array) do
        if v == value then
            return i
        end
    end
    return nil
end
print(indexOf(t, 'c'));