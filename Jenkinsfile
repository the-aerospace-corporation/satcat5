// Copyright 2020, 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

// For more information on the required Jenkins environment,
// refer to "docs/DEVOPS.md".

// Shortcut function: Shell command (sh) that notes the responsible node.
def sh_node (String cmd) {
    sh label: this.env.NODE_NAME, script: cmd
}

pipeline {
    agent any

    options {
        timeout(time: 240, unit: 'MINUTES')
        timestamps()              // Prepends timestap to build messages
        disableConcurrentBuilds() // Prevent two concurrent runs
        parallelsAlwaysFailFast() // Fail as soon as any parallel stage fails
    }

    environment {
        VIVADO_VERSION = "2016.3"
        DOCKER_REG = "dcid.aero.org:5000"
        DOCKER_DEVTOOL = "dev_tools:1.0"
        DOCKER_LIBERO = "libero:12.3"
        DOCKER_VIVADO = "vivado:2016.3"
        DOCKER_YOSYS  = "open-fpga-toolchain:latest"
    }

    stages {
        stage('SW-Test') {
            agent { label 'docker' }
            steps {
                sh_node './start_docker.sh $DOCKER_DEVTOOL make sw_coverage'
                dir('./sim/cpp') {
                    // Archive the basic coverage reports
                    archiveArtifacts artifacts: 'coverage.txt'
                    archiveArtifacts artifacts: 'coverage.xml'
                    // Fancy HTML coverage viewer
                    cobertura coberturaReportFile: 'coverage.xml'
                    publishHTML target: [
                        allowMissing: true,
                        alwaysLinkToLastBuild: false,
                        keepAll: true,
                        reportDir: './coverage/',
                        reportFiles: 'coverage.html',
                        reportName: "Coverage with Source",
                        reportTitles: ''
                    ]
                }
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    // Run the tool again, throws error below designated coverage threshold.
                    sh_node './start_docker.sh $DOCKER_DEVTOOL make sw_covertest'
                }
            }
        }
        stage('HW-Build') {
            when { not { expression { env.BRANCH_NAME ==~ 'software.*' } } }
            parallel {
                stage('Sims') {
                    agent { label 'docker' }
                    steps {
                        sh_node './start_docker.sh $DOCKER_VIVADO make sims'
                    }
                    post { success {
                        // junit has issues with paths, so soft-link it first
                        sh_node 'ln -s sim/vhdl/sim_results.xml $WORKSPACE'
                        junit 'sim_results.xml'
                        // Archive sim results
                        archiveArtifacts artifacts: 'sim/vhdl/xsim_tmp/simulate_*.log'
                    } }
                }
                stage('Arty-35T') {
                    agent { label 'docker' }
                    steps {
                        sh_node './start_docker.sh $DOCKER_VIVADO make arty_35t'
                    }
                    post { success { dir('examples/arty_a7/switch_arty_a7_35t/switch_arty_a7_35t.runs/impl_1') {
                        archiveArtifacts artifacts: '*.rpt'
                        archiveArtifacts artifacts: 'switch_top_arty_a7_rmii.bit'
                    } } }
                }
                stage('Arty-Managed') {
                    agent { label 'docker' }
                    steps {
                        sh_node './start_docker.sh $DOCKER_VIVADO make arty_managed_35t'
                    }
                    post { success {
                        dir('examples/arty_managed/arty_managed_35t/arty_managed_35t.runs/impl_1') {
                            archiveArtifacts artifacts: '*.rpt'
                        }
                        dir('examples/arty_managed') {
                            archiveArtifacts artifacts: 'arty_managed.hdf'
                            archiveArtifacts artifacts: 'arty*.bit'
                            archiveArtifacts artifacts: 'arty*.bin'
                        }
                    } }
                }
                stage('AC701-SGMII') {
                    agent { label 'docker' }
                    steps {
                        sh_node './start_docker.sh $DOCKER_VIVADO make proto_v1_sgmii'
                    }
                    post { success { dir('examples/ac701_proto_v1/switch_proto_v1_sgmii/switch_proto_v1_sgmii.runs/impl_1') {
                        archiveArtifacts artifacts: '*.rpt'
                        archiveArtifacts artifacts: 'switch_top_ac701_sgmii.bit'
                    } } }
                }
                stage('AC701-Router') {
                    agent { label 'docker' }
                    steps {
                        sh_node './start_docker.sh $DOCKER_VIVADO make ac701_router'
                    }
                    post { success { dir('examples/ac701_router/router_ac701/router_ac701.runs/impl_1') {
                        archiveArtifacts artifacts: '*.rpt'
                        archiveArtifacts artifacts: 'router_ac701_wrapper.bit'
                    } } }
                } /* Disable polarfire build due to Jenkins licensing and permission issues
                stage('MPF-Splash') {
                    agent { label 'docker' }
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') { retry(2) {
                            sh_node './start_docker.sh $DOCKER_LIBERO ./examples/mpf_splash/make_project.sh'
                        } }
                    }
                    post { success { 
                        dir('examples/mpf_splash/switch_mpf_splash_rgmii_100T/designer/switch_top_mpf_splash_rgmii') {
                            archiveArtifacts artifacts: '*has_violations,*violations*.xml,*timing_constraints_coverage.xml'
                        }
                        dir('examples/mpf_splash/switch_mpf_splash_rgmii_100T') {
                            archiveArtifacts artifacts: 'switch_mpf_splash_rgmii_100T.job'
                            archiveArtifacts artifacts: 'switch_mpf_splash_rgmii_100T_job.digest'
                        } 
                    } }
                } */
                stage('iCE40-rmii-serial') {
                    agent { label 'docker' }
                    steps {
                        sh_node './start_docker.sh $DOCKER_YOSYS make ice40_rmii_serial'
                    }
                    post { success { dir('examples/ice40_hx8k/switch_top_rmii_serial_adapter') {
                        archiveArtifacts artifacts: 'switch_top_rmii_serial_adapter.bin'
                    } } }
                }
            }
        }
    }
}
