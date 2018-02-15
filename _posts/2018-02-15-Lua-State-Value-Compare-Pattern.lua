local byte = string.byte
local char = string.char
local format = string.format
local random = math.random

local function IncAndPushCharInArray(offset, count, array)
    for i = 1, count do
        table.insert( array, char(offset + i) )
    end
    return array
end

local function GenerateCharPool()
    local pool = {'_'}
    IncAndPushCharInArray(byte('a') - 1, 26, pool)
    IncAndPushCharInArray(byte('A') - 1, 26, pool)
    return pool
end
local idenitify_chars = GenerateCharPool()

local function GenerateRandomString(chars_pool, min_len, max_len)
    local chars = {}
    local pool_size = #chars_pool
    for i=1, random(min_len, max_len) do
        table.insert(chars, chars_pool[random(pool_size)])
    end
    return table.concat( chars, '')
end

local function GenerateStringCompareTestCase(compare_n, strings_n, min_len, max_len)
    local strings = {}
    for i = 1, strings_n do
        table.insert(strings, GenerateRandomString(idenitify_chars,min_len,max_len))
    end
    local compare_statements = {}
    for i = 1, compare_n do
        --table.insert(compare_statements, format('if "%s" == "%s" then true_n = true_n + 1 else false_n = false_n + 1 end',
        --    strings[random(strings_n)], strings[random(strings_n)]))
        table.insert(compare_statements, format('str = "%s"\nif str == "%s" then end',
            strings[random(strings_n)], strings[random(strings_n)]))
    end
    compare_statements = table.concat( compare_statements, '\n')
    return format([[local clock = os.clock
local true_n = 0
local false_n = 0
local str = ''
local start = clock()
%s
local finish = clock()
print('count true:', true_n, 'false:', false_n)
print('Compare %d times, %d strings, min_len:%d, max_len:%d, cost:'..(finish - start) .. 's')
]], compare_statements, compare_n, strings_n, min_len, max_len)
end

local function GenerateNumberCompareTestCase(compare_n, n)
    local statements = {}
    for i = 1, compare_n do
        --table.insert(statements, format('if %d == %d then true_n = true_n + 1 else false_n = false_n + 1 end'
        --, random(n), random(n)))
        table.insert(statements, format('num = %d\nif num == %d then true_n = true_n end'
        , random(n), random(n)))
    end
    statements = table.concat(statements, '\n')
    return format([[local clock = os.clock
local true_n = 0
local false_n = 0
local num = 0
local start = clock()
%s
local finish = clock()
print('count true:', true_n, 'false:', false_n)
print('Compare %d times, %d numbers, cost:'..(finish - start) .. 's')
]], statements, compare_n, n)
end

local enum_i = 0
local function GenerateEnum(n, key_len_min, key_len_max)
    local items = {}
    local item_names = {}
    for i=1, n do
        enum_i = enum_i + 1
        local item_name = GenerateRandomString(idenitify_chars,key_len_min,key_len_max)
        table.insert( items, format("%s = %d", item_name, enum_i))
        table.insert( item_names, item_name)
    end
    local enum_name = format('enum_%s', GenerateRandomString(idenitify_chars,key_len_min,key_len_max))
    return enum_name, item_names, format('local %s ={%s}', enum_name,
                table.concat(items, ',\n'))
end

local function EnumElementRef(enum_name, item_name)
    return enum_name .. '.' .. item_name
end

local function GenerateEnumCompareTestCase(compare_n, enum_n, items_n, key_len_min, key_len_max)
    local enums = {}
    local names = {}
    local items = {}
    local set = {}
    for i=1, enum_n do
        local name, item, enum = GenerateEnum(items_n, key_len_min, key_len_max)
        if set[name] then
            repeat
                name, item, enum = GenerateEnum(items_n, key_len_min, key_len_max)
            until(not set[name])
        end
        set[name] = true
        table.insert( enums, enum)
        table.insert( items, item)
        table.insert( names, name)
    end
    enums = table.concat(enums, '\n')
    local statements = {}
    for i = 1, compare_n do
        local which = random(enum_n)
        local statement = format('if %d == %s then true_n = true_n + 1 else false_n = false_n + 1 end', 
            random(enum_i), EnumElementRef(names[which], items[which][random(items_n)]))
        table.insert(statements,statement)
    end
    statements = table.concat(statements, '\n')
    return format([[%s
local clock = os.clock
local true_n = 0
local false_n = 0
local start = clock()
%s
local finish = clock()
print('count true:', true_n, 'false:', false_n)
print('Compare %d times, %d enums, %d items for each enum, key_min_len:%d, key_max_len:%d, cost:'..(finish - start) .. 's')
]], enums, statements, compare_n, enum_n, items_n, key_len_min, key_len_max)
end

local compare_n = 1e6
local clock = os.clock
local test_cast = GenerateStringCompareTestCase(compare_n,1000,5, 16)
local start = clock()
local test_func = load(test_cast)
local finish = clock()
print('load short string test case cost:', finish - start)
print('FIRST CALL')
test_func()
print('SECOND CALL')
test_func()

test_cast = GenerateStringCompareTestCase(compare_n,1000,100, 200)
start = clock()
test_func = load(test_cast)
finish = clock()
print('load long string test case cost:', finish - start)
print('FIRST CALL')
test_func()
print('SECOND CALL')
test_func()

test_cast = GenerateNumberCompareTestCase(compare_n, 1000)
start = clock()
test_func = load(test_cast)
finish = clock()
print('load numbers test case cost:', finish - start)
print('FIRST CALL')
test_func()
print('SECOND CALL')
test_func()

test_cast = GenerateEnumCompareTestCase(compare_n, 100, 10, 5, 16)
start = clock()
test_func, err = load(test_cast)
if err then
    print(err)
    return
end
finish = clock()
print('load short enum test case cost:', finish - start)
print('FIRST CALL')
test_func()
print('SECOND CALL')
test_func()

test_cast = GenerateEnumCompareTestCase(compare_n, 100, 10, 100, 200)
start = clock()
test_func = load(test_cast)
finish = clock()
print('load long enum test case cost:', finish - start)
print('FIRST CALL')
test_func()
print('SECOND CALL')
test_func()
return nil
