// ------------------------------------------------------------------------
// Copyright 2019-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
// ------------------------------------------------------------------------
// Jenkinsfile for CI/CD builds of SatCat5.
//
// For more information on the required Jenkins environment,
// refer to "docs/DEVOPS.md".

// Shortcut function: Shell command (sh) that notes the responsible node.
def sh_node(String cmd) {
    sh label: this.env.NODE_NAME, script: cmd
}

// Skip time-consuming steps for software-only updates, based on branch name.
// Note: Pull-request builds should use CHANGE_BRANCH rather than BRANCH_NAME.
//  See also: https://stackoverflow.com/questions/42383273/
def build_type() {
    git_branch = "${this.env.CHANGE_BRANCH ? this.env.CHANGE_BRANCH : this.env.BRANCH_NAME}"
    return (git_branch ==~ /software(.*)/) ? "sw" : "hdl"
}

// Check for errors or critical warnings in Vivado build logs.
// (Especially useful for block-diagram projects with out-of-context runs.)
def check_vivado_build(String project_folder) {
    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
        dir(project_folder) {
            sh_node '! grep "ERROR:" */*.log'
            sh_node '! grep "CRITICAL WARNING:" */*.log'
        }
    }
}

// Pack files into a .zip file, then archive it.
def archive_zip(zipfile, srcfiles = './*') {
    docker_devtool "zip -r ${zipfile} ${srcfiles}"
    archiveArtifacts artifacts: "${zipfile}"
}

// Shortcuts for launching specific Docker images:
def docker_devtool(String cmd) {
    sh_node "${WORKSPACE}/start_docker.sh csaps/dev_tools:3.2 ${cmd}"
}
// Doxygen 1.9.1 is only available in newer, incompatible dev_tools images
def docker_doxygen(String cmd) {
    sh_node "${WORKSPACE}/start_docker.sh csaps/dev_tools:4.1 ${cmd}"
}
def docker_libero(String cmd) {
    withEnv(['DOCKER_REG=dcid.aero.org:5000']) {
        sh_node "${WORKSPACE}/start_docker.sh libero:12.3 ${cmd}"
    }
}
def docker_vivado_2016_3(String cmd) {
    withEnv(['VIVADO_VERSION=2016.3']) {
        sh_node "${WORKSPACE}/start_docker.sh csaps/vivado:2016.3_20201007 ${cmd}"
    }
}
def docker_vivado_2019_1(String cmd) {
    withEnv(['VIVADO_VERSION=2019.1']) {
        sh_node "${WORKSPACE}/start_docker.sh csaps/vivado:2019.1_20220329 ${cmd}"
    }
}
def docker_vivado_2020_2(String cmd) {
    withEnv(['VIVADO_VERSION=2020.2']) {
        sh_node "${WORKSPACE}/start_docker.sh csaps/vivado:2020.2_20220801 ${cmd}"
    }
}
def docker_yosys(String cmd) {
    sh_node "${WORKSPACE}/start_docker.sh csaps/open-fpga-toolchain:latest_04272021 ${cmd}"
}

// Run one of the parallel unit-test simulations and post results.
def run_sim(Integer phase, Integer total) {
    def work_folder = "sim/vhdl/xsim_tmp_${phase}"
    withEnv(["PARALLEL_PHASE=${phase}", "PARALLEL_SIMS=${total}"]) {
        docker_vivado_2016_3 'make sims'
    }
    dir (work_folder) {
        archive_zip("simulate_${phase}.zip", './simulate_*.log')
    }
    junit "${work_folder}/sim_results.xml"
}

pipeline {
    agent any

    options {
        timeout(time: 8, unit: 'HOURS')
        timestamps()              // Prepends timestap to build messages
        buildDiscarder(logRotator(numToKeepStr: '10')) // Limit build history
        disableConcurrentBuilds() // Prevent two concurrent runs
        parallelsAlwaysFailFast() // Fail as soon as any parallel stage fails
    }

    environment {
        ARCHIVE_FILTER = '*/*.log */*.ltx */*.rpt'
        BUILD_AGENT = 'docker && !gpuboss2'
        BUILD_TYPE = build_type()
        DOCKER_REG = 'e3-devops.aero.org'
    }

    stages {
        stage('SW-Test') {
            parallel {
                stage('Docs') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_doxygen 'make sw_docs'
                        dir('./doc') {
                            // Archive the doxygen warnings
                            archiveArtifacts artifacts: 'doxygen-warnings.log'
                            // Render HTML output
                            publishHTML target: [
                                allowMissing: false,
                                alwaysLinkToLastBuild: false,
                                keepAll: true,
                                reportDir: './docs_html/',
                                reportFiles: 'index.html',
                                reportName: 'Documentation',
                                reportTitles: ''
                            ]
                        }
                    }
                }
                stage('Linter') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        sh_node 'echo $BRANCH_NAME : $BUILD_TYPE'
                        sh_node 'echo $DOCKER_REG'
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE')
                            { docker_devtool 'make sw_cppcheck' }
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE')
                            { docker_devtool 'make sw_cpplint' }
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE')
                            { docker_devtool 'make cloc' }
                        archiveArtifacts artifacts: 'cloc.log, cppcheck.xml, cpplint.log'
                    }
                }
                stage('Tools') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_devtool 'make sw_tools'
                    }
                }
                stage('Unit tests') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_devtool 'make sw_python'
                        docker_devtool 'make sw_coverage'
                        dir('./sim/cpp') {
                            // Archive the basic coverage reports
                            archiveArtifacts artifacts: 'coverage/coverage.txt'
                            // Fancy HTML coverage viewer
                            publishHTML target: [
                                allowMissing: true,
                                alwaysLinkToLastBuild: false,
                                keepAll: true,
                                reportDir: './coverage/',
                                reportFiles: 'coverage.html',
                                reportName: 'Coverage_with_Source',
                                reportTitles: ''
                            ]
                        }
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                            // Run the tool again, throws error below designated coverage threshold.
                            docker_devtool 'make sw_covertest'
                            // Run the tool one last time, checking for leaks or unitialized memory.
                            docker_devtool 'make sw_valgrind'
                        }
                    }
                }
                // Limit to three simultaneous Vivado builds.
                // TODO: Generate simulation stages automatically?
                // Note: Auto-generated stages cannot use a declarative pipeline.
                // https://devops.stackexchange.com/questions/9887/how-to-define-dynamic-parallel-stages-in-a-jenkinsfile
                // https://www.incredibuild.com/blog/jenkins-parallel-builds-jenkins-distributed-builds
                stage('Sims 0') {
                    when { expression { env.BUILD_TYPE == 'hdl' } }
                    agent { label env.BUILD_AGENT }
                    steps { run_sim(0, 3) }
                }
                stage('Sims 1') {
                    when { expression { env.BUILD_TYPE == 'hdl' } }
                    agent { label env.BUILD_AGENT }
                    steps { run_sim(1, 3) }
                }
                stage('Sims 2') {
                    when { expression { env.BUILD_TYPE == 'hdl' } }
                    agent { label env.BUILD_AGENT }
                    steps { run_sim(2, 3) }
                }
            }
        }
        stage('HW-Build1') {
            when { expression { env.BUILD_TYPE == 'hdl' } }
            parallel {
                // Limit to three simultaneous Vivado builds.
                stage('AC701-SGMII') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2016_3 'make proto_v1_sgmii'
                        check_vivado_build 'examples/ac701_proto_v1/ac701_proto_v1/ac701_proto_v1.runs'
                        dir('examples/ac701_proto_v1/switch_proto_v1_sgmii/switch_proto_v1_sgmii.runs') {
                            archive_zip('switch_top_ac701_sgmii.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/ac701_proto_v1/switch_proto_v1_sgmii/switch_proto_v1_sgmii.runs/impl_1') {
                            archiveArtifacts artifacts: 'switch_top_ac701_sgmii.bit'
                        }
                    }
                }
                stage('Arty-35T') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2016_3 'make arty_35t'
                        check_vivado_build 'examples/arty_a7/switch_arty_a7_35t/switch_arty_a7_35t.runs'
                        dir('examples/arty_a7/switch_arty_a7_35t/switch_arty_a7_35t.runs') {
                            archive_zip('switch_top_arty_a7_rmii.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/arty_a7/switch_arty_a7_35t/switch_arty_a7_35t.runs/impl_1') {
                            archiveArtifacts artifacts: 'switch_top_arty_a7_rmii.bit'
                        }
                    }
                }
                stage('Arty-Managed') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2019_1 'make arty_managed_35t'
                        check_vivado_build 'examples/arty_managed/arty_managed_35t/arty_managed_35t.runs'
                        dir('examples/arty_managed/arty_managed_35t/arty_managed_35t.runs') {
                            archive_zip('arty_managed.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/arty_managed') {
                            archiveArtifacts artifacts: 'arty_managed.hdf'
                            archiveArtifacts artifacts: 'arty*.bit'
                            archiveArtifacts artifacts: 'arty*.bin'
                            archiveArtifacts artifacts: 'arty_managed_35t/*.svg'
                        }
                    }
                }
                // Other FPGA platforms:
                stage('MPF-Splash') {
                    agent { label env.BUILD_AGENT }
                    when { expression { false } }   // Disabled due to licensing issues.
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') { retry(2) {
                            docker_libero './examples/mpf_splash/make_project.sh'
                        } }
                        dir('examples/mpf_splash/switch_mpf_splash_rgmii_100T/designer/switch_top_mpf_splash_rgmii') {
                            archiveArtifacts artifacts: '*has_violations,*violations*.xml,*timing_constraints_coverage.xml'
                        }
                        dir('examples/mpf_splash/switch_mpf_splash_rgmii_100T') {
                            archiveArtifacts artifacts: 'switch_mpf_splash_rgmii_100T.job'
                            archiveArtifacts artifacts: 'switch_mpf_splash_rgmii_100T_job.digest'
                        }
                    }
                }
                stage('iCE40-rmii-serial') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_yosys 'make ice40_rmii_serial'
                        dir('examples/ice40_hx8k/switch_top_rmii_serial_adapter') {
                            archiveArtifacts artifacts: 'switch_top_rmii_serial_adapter.bin'
                        }
                    }
                }
            }
        }
        stage('HW-Build2') {
            when { expression { env.BUILD_TYPE == 'hdl' } }
            parallel {
                // Limit to three simultaneous Vivado builds.
                stage('AC701-Router') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2019_1 'make ac701_router'
                        check_vivado_build 'examples/ac701_router/router_ac701/router_ac701.runs'
                        dir('examples/ac701_router') {
                            archiveArtifacts artifacts: 'router_ac701/*.svg'
                        }
                        dir('examples/ac701_router/router_ac701/router_ac701.runs') {
                            archive_zip('router_ac701_wrapper.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/ac701_router/router_ac701/router_ac701.runs/impl_1') {
                            archiveArtifacts artifacts: 'router_ac701_wrapper.bit'
                        }
                    }
                }
                stage('NetFPGA') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2019_1 'make netfpga'
                        check_vivado_build 'examples/netfpga/netfpga/netfpga.runs'
                        dir('examples/netfpga/netfpga/netfpga.runs') {
                            archive_zip('netfpga.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/netfpga') {
                            archiveArtifacts artifacts: 'netfpga.hdf'
                            archiveArtifacts artifacts: 'netfpga*.bit'
                            archiveArtifacts artifacts: 'netfpga*.bin'
                            archiveArtifacts artifacts: 'netfpga/*.svg'
                        }
                    }
                }
                stage('VC707-Managed') {
                    agent { label env.BUILD_AGENT }
                    when { expression { false } }   // Disabled due to licensing issues.
                    steps {
                        docker_vivado_2019_1 'make vc707_managed'
                        check_vivado_build 'examples/vc707_managed/vc707_managed/vc707_managed.runs'
                        dir('examples/vc707_managed/vc707_managed/vc707_managed.runs') {
                            archive_zip('vc707_managed.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/vc707_managed') {
                            archiveArtifacts artifacts: 'vc707_managed/*.svg'
                            archiveArtifacts artifacts: 'vc707_managed.hdf'
                            archiveArtifacts artifacts: 'vc707*.bit'
                            archiveArtifacts artifacts: 'vc707*.bin'
                        }
                    }
                }
            }
        }
        stage('HW-Build3') {
            when { expression { env.BUILD_TYPE == 'hdl' } }
            parallel {
                // Limit to three simultaneous Vivado builds.
                stage('VC707-ClkSynth') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2019_1 'make vc707_clksynth'
                        check_vivado_build 'examples/vc707_clksynth/vc707_clksynth/vc707_clksynth.runs'
                        dir('examples/vc707_clksynth/vc707_clksynth/vc707_clksynth.runs') {
                            archive_zip('vc707_clksynth.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/vc707_clksynth/vc707_clksynth/vc707_clksynth.runs/impl_1') {
                            archiveArtifacts artifacts: 'vc707_clksynth.bit'
                        }
                    }
                }
                stage('VC707-PTP-Client') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2019_1 'make vc707_ptp_client'
                        check_vivado_build 'examples/vc707_ptp_client/vc707_ptp/vc707_ptp.runs'
                        dir('examples/vc707_ptp_client/vc707_ptp/vc707_ptp.runs') {
                            archive_zip('vc707_ptp_client.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/vc707_ptp_client') {
                            archiveArtifacts artifacts: 'vc707_ptp/*.svg'
                            archiveArtifacts artifacts: 'vc707_ptp_client.hdf'
                            archiveArtifacts artifacts: 'vc707*.bit'
                            archiveArtifacts artifacts: 'vc707*.bin'
                        }
                    }
                }
                stage('ZCU208-ClkSynth') {
                    agent { label env.BUILD_AGENT }
                    steps {
                        docker_vivado_2020_2 'make zcu208_clksynth'
                        check_vivado_build 'examples/zcu208_clksynth/zcu208_clksynth/zcu208_clksynth.runs'
                        dir('examples/zcu208_clksynth/zcu208_clksynth/zcu208_clksynth.runs') {
                            archive_zip('zcu208_clksynth.zip', env.ARCHIVE_FILTER)
                        }
                        dir('examples/zcu208_clksynth/zcu208_clksynth/zcu208_clksynth.runs/impl_1') {
                            archiveArtifacts artifacts: 'zcu208_clksynth.bit'
                        }
                    }
                }
            }
        }
    }
    post { always {
        // Keep failed builds for debugging, otherwise discard to save disk space.
        cleanWs cleanWhenFailure: false, cleanWhenUnstable: false, notFailBuild: true
    } }
}
