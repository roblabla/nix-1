#include "command.hh"
#include "common-args.hh"
#include "store-api.hh"
#include "archive.hh"
#include "posix-source-accessor.hh"

using namespace nix;

struct CmdAddToStore : MixDryRun, StoreCommand
{
    Path path;
    std::optional<std::string> namePart;
    ContentAddressMethod caMethod;

    CmdAddToStore()
    {
        // FIXME: completion
        expectArg("path", &path);

        addFlag({
            .longName = "name",
            .shortName = 'n',
            .description = "Override the name component of the store path. It defaults to the base name of *path*.",
            .labels = {"name"},
            .handler = {&namePart},
        });
    }

    void run(ref<Store> store) override
    {
        if (!namePart) namePart = baseNameOf(path);

        PosixSourceAccessor accessor;

        auto path2 = CanonPath::fromCwd(path);

        auto storePath = dryRun
            ? store->computeStorePath(
                *namePart, accessor, path2, caMethod, htSHA256, {}).first
            : store->addToStoreSlow(
                *namePart, accessor, path2, caMethod, htSHA256, {}).path;

        logger->cout("%s", store->printStorePath(storePath));
    }
};

struct CmdAddFile : CmdAddToStore
{
    CmdAddFile()
    {
        caMethod = FileIngestionMethod::Flat;
    }

    std::string description() override
    {
        return "add a regular file to the Nix store";
    }

    std::string doc() override
    {
        return
          #include "add-file.md"
          ;
    }
};

struct CmdAddPath : CmdAddToStore
{
    CmdAddPath()
    {
        caMethod = FileIngestionMethod::Recursive;
    }

    std::string description() override
    {
        return "add a path to the Nix store";
    }

    std::string doc() override
    {
        return
          #include "add-path.md"
          ;
    }
};

static auto rCmdAddFile = registerCommand2<CmdAddFile>({"store", "add-file"});
static auto rCmdAddPath = registerCommand2<CmdAddPath>({"store", "add-path"});
