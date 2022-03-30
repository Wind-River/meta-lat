inherit fullmetalupdate

LICENSE ?= "MIT"

#Add dependencies to all containers
python() {
    dependencies = " " + containers_get_dependency(d)
    d.appendVarFlag('do_initialize_ostree_containers', 'depends', dependencies)
    d.appendVarFlag('do_create_containers_package', 'depends', dependencies)
}

def containers_get_dependency(d):
    dependencies = []
    containers = (d.getVar('PREINSTALLED_CONTAINERS_LIST', True) or "").split()
    for container in containers:
        if container not in dependencies:
            dependencies.append(container)

    dependencies_string = ""
    for dependency in dependencies:
        dependencies_string += " " + dependency + ":do_build"
    return dependencies_string

do_initialize_ostree_containers() {

    if [ "${@d.getVar('PREINSTALLED_CONTAINERS_LIST')}" = '' ];then
        return
    fi
    rm -rf ${IMAGE_ROOTFS}/${APP_DIRECTORY}/*
    
    if [ -n "${PREINSTALLED_CONTAINERS_LIST}" ];then
        bbnote "Initializing a new ostree : ${IMAGE_ROOTFS}${APP_DIRECTORY}/ostree_repo"
        ostree_init ${IMAGE_ROOTFS}${APP_DIRECTORY}/ostree_repo bare-user-only
    fi
}

do_create_containers_package[depends] = " \
    ostree-native:do_populate_sysroot \
"

do_initialize_ostree_containers[depends] = " \
    ostree-native:do_populate_sysroot \
"

do_create_containers_package() {

    if [ "${@d.getVar('PREINSTALLED_CONTAINERS_LIST')}" = '' ];then
        return 
    fi 

    for container in ${PREINSTALLED_CONTAINERS_LIST}; do
        bbnote "Add a local remote on the local Docker network for ostree : ${container} ${OSTREE_HTTP_ADDRESS} ${IMAGE_ROOTFS}"
        ostree_remote_add ${IMAGE_ROOTFS}${APP_DIRECTORY}/ostree_repo ${container} ${OSTREE_HTTP_ADDRESS}
        bbnote "Pull the container: remote ${container} branch name ${container} from the repo"
        ostree_pull ${IMAGE_ROOTFS}${APP_DIRECTORY}/ostree_repo ${container} ${OSTREE_CONTAINER_PULL_DEPTH}
        bbnote "Delete the remote on the local docker network from the repo"
        ostree_remote_delete ${IMAGE_ROOTFS}${APP_DIRECTORY}/ostree_repo ${container}
        bbnote "Add a distant remote for ostree : ${OSTREE_HTTP_DISTANT_ADDRESS}"
        ostree_remote_add ${IMAGE_ROOTFS}${APP_DIRECTORY}/ostree_repo ${container} ${OSTREE_HTTP_DISTANT_ADDRESS}
        echo ${container} >> ${IMAGE_ROOTFS}${APP_DIRECTORY}/${IMAGE_NAME}-containers.manifest
    done

}

addtask create_containers_package after do_rootfs before do_image
addtask do_initialize_ostree_containers after do_rootfs before do_create_containers_package

