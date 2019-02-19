#!/bin/sh
set -u

my_where=
my_app_name="amalgomation"
my_force_overwrite=no

while true; do
    my_arg=${1-}
    
    [ ! "${my_arg}" ] && \
        break

    case ${my_arg} in
        "--temp") shift
                  my_tmp=${1-}
                  echo x$my_tmp;;
        -o|--output) shift
              my_app_name=${1-} ;;
        -f) my_force_overwrite='' ;;
        -*) echo "Unrecognized option ${my_arg}"
            exit 1 ;;
        *) echo "Add search path: ${my_arg}"
           my_where="${my_where} ${my_arg}" ;;
    esac
    shift 2>/dev/null || break
done

echo "Output name: ${my_app_name}"

# check if file exists
[ "${my_force_overwrite}" -a -e "${my_app_name}" ] && \
    echo "File already exists" && exit 1

# helper functions
my_copy() {
    from=${1}
    cp -r ${from} ${my_tmp}/
    echo $(basename ${from})
}

my_prepare_src() {
    my_dir="${1}"
    find "${my_dir}" -name '*.go' \
        -exec sed -i 's/package main$/package my_main/1' {} ';' \
        -exec sed -i 's/^func main() {$/func My_main() {/1' {} ';'
}

my_commands=

for path in ${my_where}; do
    expand=$(find ${path}/cmd -mindepth 1 -type d)
    [ $? -eq 0 ] && my_commands="${my_commands} $expand"
done

if [ -z "${my_commands}" ]; then
    echo "No cmd dirs found in given path(s)"
    exit 1
fi

my_tmp=$(mktemp -d)
my_imports=""
my_invocations=""
my_id=1
my_apps=""

for my_cmd in ${my_commands}; do
    echo "Processing ${my_cmd}"
    my_local_copy_name=$(my_copy ${my_cmd})
    my_local_copy=${my_tmp}/${my_local_copy_name}
    my_prepare_src "${my_local_copy}"

    my_module_name=m${my_id}
    my_imports="${my_imports} ${my_module_name} \"./${my_local_copy_name}\"\n"
    my_invocations="${my_invocations}case \"${my_local_copy_name}\": ${my_module_name}.My_main()\n"
    my_apps="${my_apps} ${my_local_copy_name}"
    my_id=$((${my_id}+1))
done


echo "Generating main.go"

# headers and imports
cat << EOF > ${my_tmp}/main.go
package main
import (
    "os"
    "path"
EOF

# dynamic imports
echo ${my_imports} >> ${my_tmp}/main.go

# main function
cat << EOF >> ${my_tmp}/main.go
)
func main() {
    n := path.Base(os.Args[0])
    if n == "${my_app_name}" && len(os.Args) > 1 {
        os.Args = os.Args[1:]
        n = path.Base(os.Args[0])
    }

    switch n {
EOF

# dynamic invocations
echo ${my_invocations} >> ${my_tmp}/main.go

# footer
cat << EOF >> ${my_tmp}/main.go
        case "${my_app_name}": println("Supported apps:", "${my_apps}")
        default: println("Unknown app", n)
        println("Supported apps:", "${my_apps}")
    }
}
EOF

echo "Building"

my_top=${PWD}
cd ${my_tmp}
go build ${GOFLAGS:-} -o ${my_app_name} . && cp ${my_app_name} ${my_top}/ || echo "Build failed"

# cleanup tmp directory
rm -rf ${my_tmp}
echo "done"

