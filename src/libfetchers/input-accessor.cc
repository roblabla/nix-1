#include "input-accessor.hh"
#include "store-api.hh"

namespace nix {

SourcePath InputAccessor::root()
{
    return {ref(shared_from_this()), CanonPath::root};
}

std::ostream & operator << (std::ostream & str, const SourcePath & path)
{
    str << path.to_string();
    return str;
}

StorePath SourcePath::fetchToStore(
    Store & store,
    std::string_view name,
    ContentAddressMethod method,
    PathFilter & filter,
    RepairFlag repair) const
{
    return
        settings.readOnlyMode
        ? store.computeStorePath(
            name, *accessor, path, method, htSHA256, {}, filter).first
        : store.addToStore(
            name, *accessor, path, method, htSHA256, {}, filter, repair);
}

std::string_view SourcePath::baseName() const
{
    return path.baseName().value_or("source");
}

SourcePath SourcePath::parent() const
{
    auto p = path.parent();
    assert(p);
    return {accessor, std::move(*p)};
}

SourcePath SourcePath::resolveSymlinks() const
{
    auto res = accessor->root();

    int linksAllowed = 1024;

    std::list<std::string> todo;
    for (auto & c : path)
        todo.push_back(std::string(c));

    while (!todo.empty()) {
        auto c = *todo.begin();
        todo.pop_front();
        if (c == "" || c == ".")
            ;
        else if (c == "..")
            res.path.pop();
        else {
            res.path.push(c);
            if (auto st = res.maybeLstat(); st && st->type == InputAccessor::tSymlink) {
                if (!linksAllowed--)
                    throw Error("infinite symlink recursion in path '%s'", path);
                auto target = res.readLink();
                res.path.pop();
                if (hasPrefix(target, "/"))
                    res.path = CanonPath::root;
                todo.splice(todo.begin(), tokenizeString<std::list<std::string>>(target, "/"));
            }
        }
    }

    return res;
}

}
